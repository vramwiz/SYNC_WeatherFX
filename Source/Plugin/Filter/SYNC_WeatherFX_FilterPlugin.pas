unit SYNC_WeatherFX_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// 天気演出の登録とホスト画像の入出力。描画資源はエフェクトごとに保持する。

interface

uses
  AviUtl2FilterTypes;

// 初回にコールバックを登録し、DLL 所有のテーブルを返す。
// 呼出側で解放しない。ホスト所有のポインターは保存しない。
function GetWeatherFXFilterTable: PFILTER_PLUGIN_TABLE;

const
  WEATHERFX_REQUIRED_VERSION = 2011600;

implementation

uses
  System.SysUtils, System.SyncObjs, Winapi.Windows,
  PluginFilterTable, WeatherFX_Settings, WeatherFX_Parameters,
  WeatherFX_Renderer, WeatherFX_Raster, WeatherFX_SceneSettings;

const
  EFFECT_NAME = '天気演出';
  EFFECT_GROUP = 'SYNC';

var
  PluginTableInitialized: Boolean;

type
  TWeatherSession = class
  private
    FLock: TCriticalSection;
    FRenderer: TWeatherRenderer;
    FInput,FOutput: TWeatherPixels;
  public
    constructor Create;
    destructor Destroy; override;
    // ホストのポインターは呼出中だけ借用する。設定と画像は自分のバッファへ複製する。
    function Render(Video: PFILTER_PROC_VIDEO): Byte;
  end;

constructor TWeatherSession.Create;
begin
  inherited;
  FLock:=TCriticalSection.Create;
  FRenderer:=TWeatherRenderer.Create;
end;

destructor TWeatherSession.Destroy;
begin FRenderer.Free; FLock.Free; inherited end;

function TWeatherSession.Render(Video: PFILTER_PROC_VIDEO): Byte;
var Width,Height: Integer; S: TWeatherSettings;
begin
  Result:=0;
  if not Assigned(Video^.SetImageData) then Exit;
  Width:=Video^.Object_^.Width; Height:=Video^.Object_^.Height;
  if (Width<=0) or (Height<=0) then
  begin
    if Video^.Scene=nil then Exit;
    Width:=Video^.Scene^.Width; Height:=Video^.Scene^.Height;
  end;
  if (Width<=0) or (Height<=0) or (Width>8192) or (Height>8192) or
    (Int64(Width)*Height>WEATHER_MAX_PIXELS) then Exit;
  FLock.Acquire;
  try
    if Assigned(Video^.GetImageData) and (Video^.Object_^.Width=Width) and
      (Video^.Object_^.Height=Height) then
    begin
      SetLength(FInput,Width*Height);
      Video^.GetImageData(@FInput[0]);
    end else FInput:=nil;
    if ReadWeatherRenderMode=wmIntegrated then
      FRenderer.RenderIntegrated(FInput,Width,Height,Video^.Object_^.Time,ReadWeatherSceneSettings,FOutput)
    else
    begin
      S:=ReadWeatherFXSettings;
      FRenderer.Render(FInput,Width,Height,Video^.Object_^.Time,S,FOutput);
    end;
    if Length(FOutput)<>Width*Height then Exit;
    Video^.SetImageData(@FOutput[0],Width,Height);
    Result:=1;
  finally
    FLock.Release;
  end;
end;

// DLL境界で例外を捕捉する。無効な呼出しと描画失敗は0を返す。
function WeatherFXProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result:=0;
  if (Video=nil) or (Video^.Object_=nil) or (Video^.UserData=nil) then Exit;
  try
    Result:=TWeatherSession(Video^.UserData).Render(Video);
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_WeatherFX render: '+E.Message));
  end;
end;

// インスタンス所有の描画器とロックを作成し、func_destroyで回収する。
function WeatherFXCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result:=nil;
  try Result:=TWeatherSession.Create except end;
end;

procedure WeatherFXDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try TWeatherSession(UserData).Free except end;
end;

function GetWeatherFXFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not PluginTableInitialized then
  begin
    // AquaFXと同じ単体フィルターとして登録する。メディア入力用フラグとは混在させない。
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA,
      EFFECT_NAME, EFFECT_GROUP, '天気演出 / SYNC_WeatherFX v0.3.2',
      WeatherFXProcVideo, nil);
    RegisterWeatherFXParameters;
    GetPluginTable^.Func_Create:=WeatherFXCreate;
    GetPluginTable^.Func_Destroy:=WeatherFXDestroy;
    PluginTableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
