unit WeatherFX_Renderer;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 統合天気と従来の個別演出を描くCPU描画器。フレームバッファと作業格子を所有する。

interface

uses WeatherFX_Settings, WeatherFX_Raster, WeatherFX_Clouds,
  WeatherFX_SceneSettings, WeatherFX_SceneRenderer;

type
  TWeatherRenderer = class
  private
    FCanvas: TWeatherRaster;
    FClouds: TWeatherCloudField;
    FScene: TWeatherSceneRenderer;
  public
    constructor Create;
    destructor Destroy; override;
    // Inputは呼出中だけ借用し、Outputは描画器所有配列の参照を返す。
    // 次のRenderまでに利用すること。ホスト所有ポインターを保持しない。
    // 無効サイズは空配列、強さ0は入力の複製（入力なしでは透明）を返す。
    procedure Render(const Input: TWeatherPixels; Width,Height: Integer;
      Time: Double; const Settings: TWeatherSettings; out Output: TWeatherPixels);
    // 統合型も同じフレームバッファを再利用する。無効サイズは画像を返さない。
    procedure RenderIntegrated(const Input: TWeatherPixels; Width,Height: Integer;
      Time: Double; const Settings: TWeatherSceneSettings; out Output: TWeatherPixels);
  end;

implementation

uses System.Math, WeatherFX_Celestial, WeatherFX_Particles;

constructor TWeatherRenderer.Create;
begin
  inherited;
  FCanvas:=TWeatherRaster.Create;
  FClouds:=TWeatherCloudField.Create;
  FScene:=TWeatherSceneRenderer.Create;
end;

destructor TWeatherRenderer.Destroy;
begin FScene.Free; FClouds.Free; FCanvas.Free; inherited end;

procedure TWeatherRenderer.Render(const Input: TWeatherPixels; Width,Height: Integer;
  Time: Double; const Settings: TWeatherSettings; out Output: TWeatherPixels);
var S: TWeatherSettings; Track: TWeatherTrack;
begin
  Output:=nil;
  if (Width<=0) or (Height<=0) or (Width>8192) or (Height>8192) or
    (Int64(Width)*Height>WEATHER_MAX_PIXELS) then Exit;
  S:=Settings;
  S.Family:=WeatherPreset(S.Style).Family;
  for Track:=Low(TWeatherTrack) to High(TWeatherTrack) do
    S.Values[Track]:=WeatherClampTrack(Track,S.Values[Track]);
  if IsNan(Time) or IsInfinite(Time) then Time:=0;
  Time:=EnsureRange(Time,-1E9,1E9);
  FCanvas.BeginFrame(Input,Width,Height,S.Values[wtStrength]/100);
  if S.Values[wtStrength]>0 then
    case S.Family of
      wfCloud: FClouds.Render(FCanvas,S,Time);
      wfStars,wfMeteor,wfRain,wfSnow: RenderWeatherParticles(FCanvas,S,Time);
    else RenderCelestial(FCanvas,S,Time);
    end;
  Output:=FCanvas.Pixels;
end;

procedure TWeatherRenderer.RenderIntegrated(const Input: TWeatherPixels; Width,Height: Integer;
  Time: Double; const Settings: TWeatherSceneSettings; out Output: TWeatherPixels);
begin
  Output:=nil;
  if (Width<=0) or (Height<=0) or (Width>8192) or (Height>8192) or
    (Int64(Width)*Height>WEATHER_MAX_PIXELS) then Exit;
  if IsNan(Time) or IsInfinite(Time) then Time:=0;
  Time:=EnsureRange(Time,-1E9,1E9);
  FCanvas.BeginFrame(Input,Width,Height,1);
  FScene.Render(FCanvas,FClouds,Settings,Time);
  Output:=FCanvas.Pixels;
end;

end.
