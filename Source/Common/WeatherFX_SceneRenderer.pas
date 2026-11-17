unit WeatherFX_SceneRenderer;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 時刻・曇り具合と独立した天候量を、既存描画器のレイヤーへ変換する。プリセット選択値は参照しない。

interface

uses WeatherFX_SceneSettings, WeatherFX_Raster, WeatherFX_Clouds, WeatherFX_Atmosphere;

type
  TWeatherSceneRenderer = class
  private
    FAtmosphere: TWeatherAtmosphere;
    FCache: TWeatherPixels;
    FLastSettings: TWeatherSceneSettings;
    FCacheWidth,FCacheHeight: Integer;
    FCacheValid: Boolean;
    FBaseCache: TWeatherPixels;
    FBaseSettings: TWeatherSceneSettings;
    FBaseWidth,FBaseHeight: Integer;
    FBaseValid: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    // CanvasとCloudsは呼出中だけ借用。画像を消さずに各現象を順番に合成する。
    procedure Render(C: TWeatherRaster; Clouds: TWeatherCloudField;
      const Settings: TWeatherSceneSettings; Time: Double);
  end;

implementation

uses System.Math, System.SysUtils, AviUtl2FilterTypes,
  WeatherFX_Math, WeatherFX_Settings, WeatherFX_Celestial, WeatherFX_Particles;

function ColorCode(const C: TWeatherRGB): Cardinal;
begin Result:=(Cardinal(Round(Sat(C.R)*255)) shl 16) or
  (Cardinal(Round(Sat(C.G)*255)) shl 8) or Cardinal(Round(Sat(C.B)*255)) end;

procedure HourPalette(Hour: Double; out Top,Horizon,Bottom: TWeatherRGB);
const Hours: array[0..10] of Double = (0,4.5,6.5,8.5,12,16,18,20,22,23.5,24);
  Tops: array[0..10] of Cardinal = ($030A21,$08132E,$2F537C,$1762B5,$1762B5,$1762B5,$30456F,$182447,$030A21,$030A21,$030A21);
  Horizons: array[0..10] of Cardinal = ($23375A,$3A4265,$DE9E8B,$B9DEEE,$B9DEEE,$B9DEEE,$DF8F74,$B58A9D,$23375A,$23375A,$23375A);
  Bottoms: array[0..10] of Cardinal = ($112548,$413F65,$EBA979,$4391DA,$4391DA,$4391DA,$D9654E,$75658F,$112548,$112548,$112548);
var I: Integer; U,H: Double;
begin
  H:=Wrap(Hour,24); I:=0;
  while (I<High(Hours)-1) and (H>Hours[I+1]) do Inc(I);
  U:=Smooth(Hours[I],Hours[I+1],H);
  Top:=RGBMix(RGB(Tops[I]),RGB(Tops[I+1]),U);
  Horizon:=RGBMix(RGB(Horizons[I]),RGB(Horizons[I+1]),U);
  Bottom:=RGBMix(RGB(Bottoms[I]),RGB(Bottoms[I+1]),U);
end;

constructor TWeatherSceneRenderer.Create;
begin inherited; FAtmosphere:=TWeatherAtmosphere.Create end;
destructor TWeatherSceneRenderer.Destroy;
begin FAtmosphere.Free; inherited end;

procedure TWeatherSceneRenderer.Render(C: TWeatherRaster; Clouds: TWeatherCloudField;
  const Settings: TWeatherSceneSettings; Time: Double);
var W: TWeatherSceneSettings; Track: TWeatherSceneTrack; S: TWeatherSettings;
  H,O,SkyOvercast,CloudDarkening,Clarity,Day,Warm,Twilight,WindX,WindY,VX,VY,SunVisibility: Double;
  Top,Horizon,Bottom,CloudColor,FogColor,Gray: TWeatherRGB;
  Cacheable,BaseCacheable,BaseHit: Boolean; Dest: TWeatherPixels;

  procedure Style(Value: TWeatherStyle; Amount: Double; X: Double = 0; Y: Double = 0);
  begin
    S:=WeatherPreset(Value); S.Values[wtSeed]:=W.Seed;
    C.SetLayer(Amount/100,X,Y);
  end;

begin
  W:=Settings;
  for Track:=Low(TWeatherSceneTrack) to High(TWeatherSceneTrack) do
    W.Values[Track]:=ClampSceneTrack(Track,W.Values[Track]);
  W.Seed:=EnsureRange(W.Seed,0,1000000);
  // 背景が全面不透明で、秒時刻で変化する現象がない場合だけ完成画像を再利用する。
  // キーは現在の全設定・解像度であり、プリセット番号と再生順には依存しない。
  Cacheable:=W.DrawSky and (W.Values[stWindSpeed]=0) and
    (W.Values[stRain]=0) and (W.Values[stSnow]=0) and (W.Values[stAurora]=0) and
    (W.Values[stLightning]=0) and (W.Values[stStars]=0) and (W.Values[stMeteors]=0) and
    (W.Values[stSunlight]=0) and (W.Values[stMoonlight]=0) and
    (W.Values[stHeatHaze]=0) and (W.Values[stMirage]=0);
  if Cacheable and FCacheValid and (FCacheWidth=C.Width) and (FCacheHeight=C.Height) and
    (W.DrawSky=FLastSettings.DrawSky) and (W.DoubleRainbow=FLastSettings.DoubleRainbow) and
    (W.Seed=FLastSettings.Seed) and
    CompareMem(@W.Values[Low(TWeatherSceneTrack)],@FLastSettings.Values[Low(TWeatherSceneTrack)],SizeOf(W.Values)) then
  begin
    Dest:=C.Pixels; Move(FCache[0],Dest[0],Length(FCache)*SizeOf(TPIXEL_RGBA)); Exit;
  end;
  H:=Wrap(W.Values[stHour],24); O:=W.Values[stOvercast]/100;
  // 白い雲が増える段階では青空を保ち、厚い曇天に近づいてから減光と灰色化を強める。
  SkyOvercast:=O*Smooth(0.45,0.90,O);
  CloudDarkening:=O*O*Smooth(0.25,0.85,O);
  Day:=Smooth(5,8,H)*(1-Smooth(17,21,H));
  Warm:=Max(Exp(-Sqr((H-6.5)/1.5)),Exp(-Sqr((H-18)/1.5)));
  Twilight:=Max(1-Smooth(0.25,1.25,Abs(H-6)),1-Smooth(0.25,1.25,Abs(H-18)));
  SunVisibility:=1-W.Values[stSunTransparency]/100;
  WindX:=W.Values[stWindSpeed]*4*Cos(DegToRad(Wrap(W.Values[stWindDirection],360)));
  WindY:=W.Values[stWindSpeed]*4*Sin(DegToRad(Wrap(W.Values[stWindDirection],360)));
  HourPalette(H,Top,Horizon,Bottom);
  Clarity:=Day*(1-Warm)*Smooth(0,0.12,O)*(1-Smooth(0.55,0.85,O));
  Top:=RGBMix(Top,RGB($075DC7),Clarity*0.94);
  Horizon:=RGBMix(Horizon,RGB($3D9FEB),Clarity*0.94);
  Bottom:=RGBMix(Bottom,RGB($2E97DE),Clarity*0.94);
  Gray:=RGBScale(RGBMix(RGB($65707C),RGB($5F4554),Warm*0.45),Mix(0.10,0.72,Day));
  Top:=RGBMix(Top,Gray,SkyOvercast*0.90); Horizon:=RGBMix(Horizon,Gray,SkyOvercast*0.94);
  Bottom:=RGBMix(Bottom,Gray,SkyOvercast*0.92);
  // 風・降水だけが動くフレームでは、時刻設定に従う空と天体の不透明な背景を再利用する。
  BaseCacheable:=W.DrawSky and (W.Values[stStars]=0) and (W.Values[stAurora]=0);
  BaseHit:=BaseCacheable and FBaseValid and (C.Width=FBaseWidth) and (C.Height=FBaseHeight) and
    (W.Seed=FBaseSettings.Seed) and (W.DoubleRainbow=FBaseSettings.DoubleRainbow) and
    CompareMem(@W.Values[Low(TWeatherSceneTrack)],@FBaseSettings.Values[Low(TWeatherSceneTrack)],SizeOf(W.Values));
  if BaseHit then
  begin
    Dest:=C.Pixels; Move(FBaseCache[0],Dest[0],Length(FBaseCache)*SizeOf(TPIXEL_RGBA));
  end else
  begin
  if W.DrawSky then
  begin
    C.SetLayer(1);
    if Twilight>0 then RenderTwilightSky(C,Top,Horizon,Bottom,Twilight,O,C.Width/2+W.Values[stSunX],H<12)
    else RenderSkyPalette(C,Top,Horizon,Bottom,1);
  end;
  if W.Values[stStars]>0 then
  begin
    Style(wsTwinklingStars,W.Values[stStars]); S.Values[wtAmount]:=230;
    S.Values[wtSize]:=W.Values[stStarSize];
    RenderWeatherParticles(C,S,Time,True);
  end;
  FAtmosphere.Aurora(C,W.Values[stAurora],Time,W.Seed);
  if (SunVisibility>0) and (W.Values[stSunSize]>0) then
  begin
    Style(wsSun,SunVisibility*100*Mix(1,0.08,SkyOvercast),W.Values[stSunX],W.Values[stSunY]);
    S.Values[wtSize]:=W.Values[stSunSize];
    // 統合型の太陽の状態は「時刻」で制御し、表面模様は固定する。
    S.Values[wtSpeed]:=0;
    S.Values[wtGlow]:=100; S.Values[wtBrightness]:=Mix(145,115,Twilight); S.Values[wtBlur]:=0.6;
    S.ColorRGB:=ColorCode(RGBMix(RGB($FFF1CD),RGB($FF9657),Max(Warm,1-Day)*0.9));
    S.ColorRGB:=ColorCode(RGBMix(RGB(S.ColorRGB),RGB($FFAD4F),Twilight*0.65));
    RenderSunLight(C,S,Time);
  end;
  if (W.Values[stMoonTransparency]<100) and (W.Values[stMoonSize]>0) then
  begin
    Style(wsFullMoon,100-W.Values[stMoonTransparency],W.Values[stMoonX],W.Values[stMoonY]);
    S.Values[wtSize]:=W.Values[stMoonSize]; S.Values[wtShape]:=W.Values[stMoonPhase];
    S.Values[wtAngle]:=W.Values[stMoonDirection]; RenderCelestial(C,S,Time);
  end;
  if (W.Values[stRainbowTransparency]<100) and (W.Values[stRainbowRadius]>0) and
    (W.Values[stRainbowArc]>0) and (W.Values[stRainbowWidth]>0) then
  begin
    Style(wsRainbow,100-W.Values[stRainbowTransparency],W.Values[stRainbowX],W.Values[stRainbowY]);
    S.Values[wtSize]:=W.Values[stRainbowRadius];
    if W.DoubleRainbow then S.Values[wtAmount]:=2;
    RenderRainbowLayer(C,S,W.Values[stRainbowWidth],W.Values[stRainbowArc],True);
  end;
  if BaseCacheable then
  begin
    Dest:=C.Pixels; SetLength(FBaseCache,Length(Dest));
    Move(Dest[0],FBaseCache[0],Length(Dest)*SizeOf(TPIXEL_RGBA));
    FBaseSettings:=W; FBaseWidth:=C.Width; FBaseHeight:=C.Height; FBaseValid:=True;
  end else FBaseValid:=False;
  end;
  CloudColor:=RGBMix(RGBScale(RGB($FFFFFF),Mix(0.13,1,Day)),
    RGBScale(RGB($FFA574),Mix(0.35,0.95,Day)),Warm*0.7);
  CloudColor:=RGBMix(CloudColor,RGBScale(RGB($545D6B),Mix(0.16,1,Day)),CloudDarkening);
  CloudColor:=RGBMix(CloudColor,RGB($FFD08C),Twilight*0.5*(1-CloudDarkening));
  if O>0 then
  begin
    Style(wsWhiteCloud,Mix(96,99,O)); S.ColorRGB:=ColorCode(CloudColor);
    S.Values[wtDensity]:=W.Values[stOvercast]; S.Values[wtSize]:=Max(C.Width,C.Height)*0.8;
    S.Values[wtSpeed]:=W.Values[stWindSpeed]*1.6; S.Values[wtAngle]:=Wrap(W.Values[stWindDirection],360);
    Clouds.Render(C,S,Time,True);
  end;
  if (Twilight>0) and (SunVisibility>0) then
    RenderSolarAtmosphere(C,C.Width/2+W.Values[stSunX],C.Height/2+W.Values[stSunY],
      W.Values[stSunSize],Twilight*SunVisibility*Mix(1,0.08,SkyOvercast));
  if W.Values[stSunlight]>0 then
  begin
    Style(wsSunlight,W.Values[stSunlight]*Mix(1,0.05,O),W.Values[stSunX],W.Values[stSunY]);
    S.ColorRGB:=ColorCode(RGBMix(RGB($FFF1CD),RGB($FFB887),Warm)); RenderCelestial(C,S,Time);
  end;
  if W.Values[stMoonlight]>0 then
  begin
    Style(wsMoonlight,W.Values[stMoonlight],W.Values[stMoonX],W.Values[stMoonY]);
    RenderCelestial(C,S,Time);
  end;
  if (W.Values[stMeteors]>0) and (W.Values[stMeteorFrequency]>0) then
  begin
    Style(wsMeteor,W.Values[stMeteors]);
    RenderMeteorShower(C,S,Time,W.Values[stMeteorFrequency]);
  end;
  FAtmosphere.Lightning(C,W.Values[stLightning],W.Values[stLightningWidth],W.Values[stLightningFlash],Time,W.Seed);
  FogColor:=RGBScale(RGB($F4F6F8),Mix(0.24,1,Day));
  FAtmosphere.Fog(C,W.Values[stFog],WindX*0.12,WindY*0.12,Time,W.Seed,FogColor);
  if (W.Values[stRain]>0) and (W.Values[stRainSize]>0) then
  begin
    Style(wsRain,65); S.Values[wtAmount]:=W.Values[stRain]*8.5;
    S.Values[wtSize]:=W.Values[stRainSize]; S.Values[wtSpread]:=30+W.Values[stRain]*0.5;
    VX:=WindX; VY:=600*W.Values[stFallSpeed]/100+WindY*0.3;
    S.Values[wtSpeed]:=Min(2000,Hypot(VX,VY)); S.Values[wtAngle]:=RadToDeg(ArcTan2(VY,VX));
    RenderWeatherParticles(C,S,Time,True);
  end;
  if (W.Values[stSnow]>0) and (W.Values[stSnowSize]>0) then
  begin
    Style(wsSnow,95); S.Values[wtAmount]:=W.Values[stSnow]*5.5;
    S.Values[wtSize]:=W.Values[stSnowSize]; VX:=WindX; VY:=65*W.Values[stFallSpeed]/100+WindY*0.15;
    S.Values[wtSpeed]:=Min(2000,Hypot(VX,VY)); S.Values[wtAngle]:=RadToDeg(ArcTan2(VY,VX));
    RenderWeatherParticles(C,S,Time,True);
  end;
  FAtmosphere.Wind(C,W.Values[stWindExpression],W.Values[stWindSpeed],Wrap(W.Values[stWindDirection],360),Time,W.Seed);
  FAtmosphere.Refract(C,Max(W.Values[stHeatHaze],Max(0,W.Values[stWindExpression]-50)*W.Values[stWindSpeed]*0.002),
    W.Values[stMirage],Time,W.Seed);
  FCacheValid:=Cacheable;
  if Cacheable then
  begin
    FCache:=Copy(C.Pixels); FLastSettings:=W; FCacheWidth:=C.Width; FCacheHeight:=C.Height;
  end;
end;

end.
