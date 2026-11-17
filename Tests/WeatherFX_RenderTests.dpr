program WeatherFX_RenderTests;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 本番AUF2の公開関数・標準項目・描画コールバックを検査する。AviUtl2は起動しない。

{$APPTYPE CONSOLE}
{$R+}{$Q+}

uses System.SysUtils, System.Classes, System.Math, System.Diagnostics,
  Winapi.Windows, Vcl.Imaging.pngimage,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  WeatherFX_Settings in '..\Source\Common\WeatherFX_Settings.pas',
  WeatherFX_SceneSettings in '..\Source\Common\WeatherFX_SceneSettings.pas';

type
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TRequired = function: Cardinal; cdecl;
  TUninitialize = procedure; cdecl;
  TPixels = array of TPIXEL_RGBA;
  PItem = ^TItem;
  TItem = record ItemType,Name: PWideChar end;
  TStyleOptions = array[0..WEATHER_STYLE_COUNT] of TFILTER_ITEM_SELECT_ITEM;
  PStyleOptions = ^TStyleOptions;

var
  Table: PFILTER_PLUGIN_TABLE;
  StyleItem: PFILTER_ITEM_SELECT;
  ApplyButton: PFILTER_ITEM_BUTTON;
  Tracks: array[TWeatherTrack] of PFILTER_ITEM_TRACK;
  ColorItem: PFILTER_ITEM_COLOR;
  CustomColor: PFILTER_ITEM_CHECK;
  RenderModeItem: PFILTER_ITEM_SELECT;
  WeatherPresetItem: PFILTER_ITEM_SELECT;
  WeatherApplyButton: PFILTER_ITEM_BUTTON;
  SceneTracks: array[TWeatherSceneTrack] of PFILTER_ITEM_TRACK;
  DrawSkyItem,DoubleRainbowItem: PFILTER_ITEM_CHECK;
  Video: TFILTER_PROC_VIDEO;
  Obj: TOBJECT_INFO;
  Scene: TSCENE_INFO;
  Edit: TEDIT_SECTION;
  EditInfo: TEDIT_INFO;
  Captured,HostInput: TPixels;
  SetCount,EditCount: Integer;
  EditTargetCorrect: Boolean;
  ImageDirectory: string;

procedure Check(Condition: Boolean; const MessageText: string);
begin if not Condition then raise Exception.Create(MessageText) end;

function Same(const A,B: TPixels): Boolean;
begin
  Result:=(Length(A)=Length(B)) and ((Length(A)=0) or
    CompareMem(@A[0],@B[0],Length(A)*SizeOf(TPIXEL_RGBA)));
end;

procedure GetImage(Buffer: PPIXEL_RGBA); cdecl;
begin
  if Length(HostInput)>0 then Move(HostInput[0],Buffer^,Length(HostInput)*SizeOf(TPIXEL_RGBA))
  else FillChar(Buffer^,Obj.Width*Obj.Height*SizeOf(TPIXEL_RGBA),0);
end;

procedure SetImage(Buffer: PPIXEL_RGBA; Width,Height: Integer); cdecl;
begin
  Inc(SetCount);
  Check((Width>0) and (Height>0),'Invalid output dimensions');
  SetLength(Captured,Width*Height);
  Move(Buffer^,Captured[0],Length(Captured)*SizeOf(TPIXEL_RGBA));
end;

function SetItemValue(Handle: OBJECT_HANDLE; Effect,ItemName: PWideChar; Value: PAnsiChar): Boolean; cdecl;
var Track: TWeatherTrack; SceneTrack: TWeatherSceneTrack; Text: string; Code: Cardinal;
begin
  Result:=False;
  EditTargetCorrect:=EditTargetCorrect and (Handle=Pointer(1234)) and (string(Effect)='天気演出:2');
  Text:=string(UTF8String(Value));
  for SceneTrack:=Low(TWeatherSceneTrack) to High(TWeatherSceneTrack) do
    if string(SceneTracks[SceneTrack]^.Name)=string(ItemName) then
    begin SceneTracks[SceneTrack]^.Value:=StrToFloat(Text,TFormatSettings.Invariant); Result:=True; Break end;
  for Track:=Low(TWeatherTrack) to High(TWeatherTrack) do
    if string(Tracks[Track]^.Name)=string(ItemName) then
    begin Tracks[Track]^.Value:=StrToFloat(Text,TFormatSettings.Invariant); Result:=True; Break end;
  if string(ItemName)='色' then
  begin
    Code:=StrToInt('$'+Text); ColorItem^.R:=(Code shr 16) and 255;
    ColorItem^.G:=(Code shr 8) and 255; ColorItem^.B:=Code and 255; Result:=True;
  end;
  if string(ItemName)='色を指定' then begin CustomColor^.Value:=StrToInt(Text); Result:=True end;
  if string(ItemName)='空を描画' then begin DrawSkyItem^.Value:=StrToInt(Text); Result:=True end;
  if string(ItemName)='二重虹' then begin DoubleRainbowItem^.Value:=StrToInt(Text); Result:=True end;
  if string(ItemName)='描画方式' then
  begin
    if Text='個別演出' then RenderModeItem^.Value:=Ord(wmIndividual)
    else if Text='統合天気' then RenderModeItem^.Value:=Ord(wmIntegrated)
    else Exit;
    Result:=True;
  end;
  if Result then Inc(EditCount);
end;

procedure Configure(Style: TWeatherStyle);
var Before: Integer; Track: TWeatherTrack; Preset: TWeatherSettings;
begin
  StyleItem^.Value:=Ord(Style); Before:=EditCount;
  ApplyButton^.Callback2(@Edit,Pointer(1234),'天気演出:2','設定');
  Check(EditTargetCorrect,'Preset targeted another instance');
  Check(EditCount-Before=17,'Incomplete preset application');
  Preset:=WeatherPreset(Style);
  for Track:=Low(TWeatherTrack) to High(TWeatherTrack) do
    if Track<>wtSeed then Check(Abs(Tracks[Track]^.Value-Preset.Values[Track])<1E-8,'Preset value mismatch');
  Check(Tracks[wtSeed]^.Value=17,'Preset overwrote seed');
end;

function Render(Time: Double): TPixels;
var Before: Integer;
begin
  Obj.Time:=Time; Before:=SetCount;
  Check(Table^.Func_Proc_Video(@Video)=1,'Production render failed');
  Check(SetCount=Before+1,'Output callback count mismatch');
  Result:=Copy(Captured);
end;

function Coverage(const Pixels: TPixels): Integer;
var P: TPIXEL_RGBA;
begin Result:=0; for P in Pixels do if P.A>4 then Inc(Result) end;

procedure SavePNG(const Pixels: TPixels; const FileName: string);
var PNG: TPngImage; X,Y,I: Integer; Row: PByte;
begin
  PNG:=TPngImage.CreateBlank(COLOR_RGBALPHA,8,Scene.Width,Scene.Height);
  try
    for Y:=0 to Scene.Height-1 do
    begin
      Row:=PNG.Scanline[Y];
      for X:=0 to Scene.Width-1 do
      begin
        I:=Y*Scene.Width+X; Row[X*3]:=Pixels[I].B; Row[X*3+1]:=Pixels[I].G;
        Row[X*3+2]:=Pixels[I].R; PNG.AlphaScanline[Y]^[X]:=Pixels[I].A;
      end;
    end;
    PNG.SaveToFile(ImageDirectory+FileName);
  finally PNG.Free end;
end;

procedure BindItems;
var I,N,GroupCount: Integer; Track: TWeatherTrack; SceneTrack: TWeatherSceneTrack;
  P: PItem; ItemPointer: PPointer;
begin
  ItemPointer:=PPointer(Table^.Items); N:=0; GroupCount:=0;
  Check(string(PItem(ItemPointer^)^.Name)='天気プリセット','Weather preset is not at top');
  while ItemPointer^<>nil do
  begin
    Inc(N); Check(N<100,'Unterminated items'); P:=PItem(ItemPointer^);
    if string(P^.Name)='スタイル' then StyleItem:=PFILTER_ITEM_SELECT(P);
    if string(P^.Name)='描画方式' then RenderModeItem:=PFILTER_ITEM_SELECT(P);
    if string(P^.Name)='天気プリセット' then WeatherPresetItem:=PFILTER_ITEM_SELECT(P);
    if string(P^.Name)='設定を反映' then WeatherApplyButton:=PFILTER_ITEM_BUTTON(P);
    if string(P^.Name)='空を描画' then DrawSkyItem:=PFILTER_ITEM_CHECK(P);
    if string(P^.Name)='二重虹' then DoubleRainbowItem:=PFILTER_ITEM_CHECK(P);
    if string(P^.ItemType)='group' then
    begin
      Inc(GroupCount);
      if string(P^.Name)='基本設定' then Check(PFILTER_ITEM_GROUP(P)^.DefaultVisible=1,'Basic settings are collapsed')
      else Check(PFILTER_ITEM_GROUP(P)^.DefaultVisible=0,'Detailed settings are not collapsed');
    end;
    if string(P^.Name)='設定' then ApplyButton:=PFILTER_ITEM_BUTTON(P);
    if string(P^.Name)='色' then ColorItem:=PFILTER_ITEM_COLOR(P);
    if string(P^.Name)='色を指定' then CustomColor:=PFILTER_ITEM_CHECK(P);
    for Track:=Low(TWeatherTrack) to High(TWeatherTrack) do
      if string(P^.Name)=string(WEATHER_TRACKS[Track].Name) then Tracks[Track]:=PFILTER_ITEM_TRACK(P);
    for SceneTrack:=Low(TWeatherSceneTrack) to High(TWeatherSceneTrack) do
      if string(P^.Name)=string(WEATHER_SCENE_TRACKS[SceneTrack].Name) then SceneTracks[SceneTrack]:=PFILTER_ITEM_TRACK(P);
    Inc(ItemPointer);
  end;
  Check(N=79,'Unexpected item count');
  Check(GroupCount=16,'Missing foldable groups');
  Check((WeatherPresetItem<>nil) and (WeatherApplyButton<>nil) and (DrawSkyItem<>nil) and
    (DoubleRainbowItem<>nil) and (RenderModeItem<>nil),'Missing integrated UI item');
  for SceneTrack:=Low(TWeatherSceneTrack) to High(TWeatherSceneTrack) do
    Check(SceneTracks[SceneTrack]<>nil,'Missing scene track');
  for I:=0 to WEATHER_SCENE_PRESET_COUNT-1 do
    Check(PStyleOptions(WeatherPresetItem^.List)^[I].Name<>nil,'Missing weather preset option');
  Check(PStyleOptions(WeatherPresetItem^.List)^[WEATHER_SCENE_PRESET_COUNT].Name=nil,'Unterminated weather presets');
  Check((StyleItem<>nil) and (ApplyButton<>nil) and (ColorItem<>nil) and (CustomColor<>nil),'Missing UI item');
  for Track:=Low(TWeatherTrack) to High(TWeatherTrack) do Check(Tracks[Track]<>nil,'Missing track');
  for I:=0 to WEATHER_STYLE_COUNT-1 do
    Check(PStyleOptions(StyleItem^.List)^[I].Name<>nil,'Missing style option');
  Check(PStyleOptions(StyleItem^.List)^[WEATHER_STYLE_COUNT].Name=nil,'Unterminated styles');
end;

procedure ConfigureWeather(Preset: TWeatherScenePreset);
var Before: Integer; Track: TWeatherSceneTrack; Expected: TWeatherSceneSettings;
begin
  WeatherPresetItem^.Value:=Ord(Preset); Before:=EditCount;
  EditInfo:=Default(TEDIT_INFO); EditInfo.Width:=Scene.Width; EditInfo.Height:=Scene.Height;
  Edit.Info:=@EditInfo;
  WeatherApplyButton^.Callback2(@Edit,Pointer(1234),'天気演出:2','設定を反映');
  Check(EditTargetCorrect,'Weather preset targeted another instance');
  Check(EditCount-Before=42,'Incomplete weather preset');
  Expected:=WeatherScenePreset(Preset,Scene.Width,Scene.Height);
  for Track:=Low(TWeatherSceneTrack) to High(TWeatherSceneTrack) do
    Check(Abs(SceneTracks[Track]^.Value-Expected.Values[Track])<1E-8,'Wrong weather preset value');
  Check(Tracks[wtSeed]^.Value=17,'Weather preset reset seed');
  Check(RenderModeItem^.Value=Ord(wmIntegrated),'Weather preset did not enable integrated mode');
end;

procedure IsolateWeather;
begin
  ConfigureWeather(wpClear); DrawSkyItem^.Value:=0;
  SceneTracks[stSunTransparency]^.Value:=100;
end;

function AlphaSum(const Pixels: TPixels): Int64;
var P: TPIXEL_RGBA;
begin Result:=0; for P in Pixels do Result:=Result+P.A end;

function MeanLight(const Pixels: TPixels): Double;
var P: TPIXEL_RGBA; Total: Int64;
begin
  Total:=0; for P in Pixels do Total:=Total+P.R+P.G+P.B;
  Result:=Total/Max(1,Length(Pixels))/3;
end;

function MaxColorDelta(const A,B: TPixels): Integer;
var I: Integer;
begin
  Check(Length(A)=Length(B),'Different sizes in continuity check'); Result:=0;
  for I:=0 to High(A) do Result:=Max(Result,Max(Abs(A[I].R-B[I].R),
    Max(Abs(A[I].G-B[I].G),Abs(A[I].B-B[I].B))));
end;

function CentroidX(const Pixels: TPixels): Double;
var I: Integer; Sum,Weight: Double;
begin
  Sum:=0; Weight:=0;
  for I:=0 to High(Pixels) do begin Sum:=Sum+(I mod Scene.Width)*Pixels[I].A; Weight:=Weight+Pixels[I].A end;
  Result:=Sum/Max(1,Weight);
end;

procedure RunIntegratedTests;
const Phenomena: array[0..6] of TWeatherSceneTrack = (stFog,stAurora,stWindExpression,
  stStars,stMeteors,stSunlight,stMoonlight);
var Track: TWeatherSceneTrack; Preset: TWeatherScenePreset; Defaults: TWeatherSceneSettings;
  A,B,D: TPixels; I,J,FullArea,HalfArea,MaxA: Integer; L0,L50,L100,CX,LightningTime,MeteorTime,T: Double;
  CSV: TStringList;
begin
  Defaults:=WeatherScenePreset(wpSunny);
  Check(RenderModeItem^.Value=Ord(wmIntegrated),'New object is not integrated');
  Check(WeatherPresetItem^.Value=Ord(wpSunny),'New object preset is not sunny');
  for Track:=Low(TWeatherSceneTrack) to High(TWeatherSceneTrack) do
    Check(SceneTracks[Track]^.Value=Defaults.Values[Track],'New object has wrong sunny default');
  Check(DrawSkyItem^.Value=1,'New object has no sky');
  Check((SceneTracks[stHour]^.Value=11) and (SceneTracks[stOvercast]^.Value=35) and
    (SceneTracks[stSunY]^.Value=-200) and (SceneTracks[stSunX]^.Value=160) and
    (SceneTracks[stSunSize]^.Value=64),'Sunny default tuning was lost');
  Check((SceneTracks[stWindSpeed]^.Value=10) and (SceneTracks[stWindDirection]^.Value=0) and
    (SceneTracks[stWindExpression]^.Value=0),'Sunny default wind was lost');
  A:=Render(1.25); SavePNG(A,'new_sunny.png');
  B:=Render(2.25); Check(not Same(A,B),'Default clouds do not move with timeline time');
  Tracks[wtSeed]^.Value:=17;
  A:=Render(1.25); Check(Coverage(A)=Scene.Width*Scene.Height,'Default sky is not generated');
  WeatherPresetItem^.Value:=Ord(wpDownpour); B:=Render(1.25);
  Check(Same(A,B),'Selecting a weather preset changed the picture');
  Check(SceneTracks[stRain]^.Value=0,'Selecting a preset changed rainfall');
  ConfigureWeather(wpClear); SceneTracks[stSunTransparency]^.Value:=100;
  A:=Render(1.25); Configure(wsBlueSky); B:=Render(1.25);
  Check(Same(A,B),'Noon clear sky differs from original blue sky');
  RenderModeItem^.Value:=Ord(wmIntegrated);
  SceneTracks[stHour]^.Value:=0; A:=Render(1.25);
  for I:=1 to 10 do begin SceneTracks[stHour]^.Value:=I*24; B:=Render(1.25);
    Check(Same(A,B),'24-hour wrap changed the sky') end;
  SceneTracks[stHour]^.Value:=23.999; B:=Render(1.25);
  Check(MaxColorDelta(A,B)<=1,'Midnight discontinuity');
  SceneTracks[stHour]^.Value:=6.499; A:=Render(1.25);
  SceneTracks[stHour]^.Value:=6.501; B:=Render(1.25);
  Check(MaxColorDelta(A,B)<=2,'Dawn discontinuity');
  SceneTracks[stHour]^.Value:=12; SceneTracks[stOvercast]^.Value:=0; L0:=MeanLight(Render(1.25));
  SceneTracks[stOvercast]^.Value:=50; L50:=MeanLight(Render(1.25));
  SceneTracks[stOvercast]^.Value:=100; A:=Render(1.25); L100:=MeanLight(A);
  Check((L100<L0) and (L100<L50),'Thick overcast is not darker than clear or white-cloud sky');
  for I in [35,55,75,85] do
  begin
    SceneTracks[stOvercast]^.Value:=I-0.001; B:=Render(1.25);
    SceneTracks[stOvercast]^.Value:=I+0.001; D:=Render(1.25);
    if MaxColorDelta(B,D)>3 then begin SavePNG(B,'continuity_before.png'); SavePNG(D,'continuity_after.png') end;
    Check(MaxColorDelta(B,D)<=3,Format('Cloud rendering changes abruptly around density %d (delta %d)',[I,MaxColorDelta(B,D)]));
  end;
  SceneTracks[stOvercast]^.Value:=100; A:=Render(1.25);
  WeatherPresetItem^.Value:=Ord(wpRain); B:=Render(1.25);
  Check(Same(A,B),'Cloudiness created rain through preset state');
  SceneTracks[stRain]^.Value:=50; B:=Render(1.25); Check(not Same(A,B),'Rain has no effect');
  SceneTracks[stSnow]^.Value:=50; D:=Render(1.25); Check(not Same(B,D),'Rain and snow cannot coexist');
  Check(SceneTracks[stOvercast]^.Value=100,'Precipitation changed cloudiness');
  IsolateWeather; SceneTracks[stWindSpeed]^.Value:=80; A:=Render(1.25);
  Check(Coverage(A)=0,'Wind expression zero draws streamlines');
  SceneTracks[stRain]^.Value:=50; B:=Render(1.25); SceneTracks[stWindSpeed]^.Value:=0; D:=Render(1.25);
  Check(not Same(B,D),'Wind does not affect rain');
  SceneTracks[stRain]^.Value:=0; SceneTracks[stSnow]^.Value:=60;
  SceneTracks[stWindSpeed]^.Value:=0; A:=Render(1.25);
  SceneTracks[stWindSpeed]^.Value:=80; B:=Render(1.25); Check(not Same(A,B),'Wind does not affect snow');
  SceneTracks[stWindDirection]^.Value:=360; D:=Render(1.25); Check(Same(B,D),'0/360 wind directions disagree');
  IsolateWeather; SceneTracks[stOvercast]^.Value:=50; A:=Render(1.25); B:=Render(2.25);
  Check(Same(A,B),'Wind zero moves clouds');
  SceneTracks[stWindSpeed]^.Value:=60; A:=Render(1.25); B:=Render(2.25);
  Check(not Same(A,B),'Wind does not advect clouds');
  IsolateWeather; SceneTracks[stFog]^.Value:=70; SceneTracks[stWindSpeed]^.Value:=60;
  A:=Render(1.25); B:=Render(2.25); Check(not Same(A,B),'Wind does not advect fog');
  IsolateWeather; SceneTracks[stSunTransparency]^.Value:=0; SceneTracks[stSunX]^.Value:=0;
  SceneTracks[stSunY]^.Value:=0; A:=Render(1.25); CX:=CentroidX(A);
  SceneTracks[stSunX]^.Value:=80; B:=Render(1.25);
  Check(Abs(CentroidX(B)-CX-80)<0.2,'Independent sun position failed');
  SceneTracks[stHour]^.Value:=18; D:=Render(1.25);
  for I:=0 to High(B) do Check(B[I].A=D[I].A,'Time automatically moved or clipped the sun');
  SceneTracks[stMoonTransparency]^.Value:=0; SceneTracks[stMoonX]^.Value:=-100;
  SceneTracks[stMoonY]^.Value:=0; D:=Render(1.25);
  Check(AlphaSum(D)>AlphaSum(B),'Sun and moon cannot coexist');
  SceneTracks[stSunTransparency]^.Value:=100; SceneTracks[stMoonPhase]^.Value:=100;
  FullArea:=Coverage(Render(1.25)); SceneTracks[stMoonPhase]^.Value:=50;
  HalfArea:=Coverage(Render(1.25)); Check(FullArea>HalfArea,'Integrated moon phase failed');
  SceneTracks[stMoonPhase]^.Value:=0; Check(Coverage(Render(1.25))=0,'New moon is not empty');
  IsolateWeather; SceneTracks[stRainbowTransparency]^.Value:=0; A:=Render(1.25);
  MaxA:=0; for I:=0 to High(A) do MaxA:=Max(MaxA,A[I].A);
  Check(MaxA=255,'Rainbow cannot become fully visible');
  SavePNG(A,'rainbow_solid.png'); SceneTracks[stRainbowTransparency]^.Value:=80; B:=Render(1.25);
  Check(AlphaSum(B)<AlphaSum(A)*0.25,'Rainbow transparency is ineffective'); SavePNG(B,'rainbow_faint.png');
  SceneTracks[stRainbowTransparency]^.Value:=100; Check(Coverage(Render(1.25))=0,'Hidden rainbow still renders');
  MeteorTime:=1.25;
  for Track in Phenomena do
  begin
    IsolateWeather; SceneTracks[Track]^.Value:=75; T:=1.25; A:=Render(T);
    if Track=stMeteors then
      for J:=1 to 60 do begin if Coverage(A)>0 then Break; T:=J*0.1; A:=Render(T) end;
    if Track=stMeteors then MeteorTime:=T;
    Check(Coverage(A)>0,'Additional phenomenon is invisible: '+string(WEATHER_SCENE_TRACKS[Track].Name));
    if Track in [stFog,stAurora] then SavePNG(A,Format('effect_%d.png',[Ord(Track)]));
  end;
  IsolateWeather; SceneTracks[stLightning]^.Value:=80; LightningTime:=0;
  for J:=0 to 120 do
  begin
    A:=Render(J*0.05);
    if Coverage(A)>0 then begin LightningTime:=J*0.05; Break end;
  end;
  Check(Coverage(A)>0,'Lightning never appears'); SavePNG(A,'lightning.png');
  IsolateWeather; Obj.Width:=Scene.Width; Obj.Height:=Scene.Height; Video.GetImageData:=GetImage;
  SetLength(HostInput,Scene.Width*Scene.Height);
  for I:=0 to High(HostInput) do
  begin
    HostInput[I].R:=I mod 251; HostInput[I].G:=(I div 7) mod 251;
    HostInput[I].B:=83; HostInput[I].A:=I mod 256;
  end;
  A:=Render(1.25); Check(Same(A,HostInput),'Disabled scene modified input RGBA');
  SceneTracks[stHeatHaze]^.Value:=90; B:=Render(1.25); D:=Render(1.25);
  Check(not Same(A,B),'Heat haze does not refract input'); Check(Same(B,D),'Refraction is not reproducible');
  SavePNG(B,'heat_filter.png'); SceneTracks[stHeatHaze]^.Value:=0; SceneTracks[stMirage]^.Value:=90;
  B:=Render(1.25); Check(not Same(A,B),'Mirage does not refract input'); SavePNG(B,'mirage_filter.png');
  HostInput:=nil; Obj.Width:=0; Obj.Height:=0; Video.GetImageData:=nil;
  CSV:=TStringList.Create;
  try
    CSV.Add('style,name,time');
    for Preset:=Low(TWeatherScenePreset) to High(TWeatherScenePreset) do
    begin
      ConfigureWeather(Preset); T:=1.25; if Preset=wpThunderstorm then T:=LightningTime;
      if Preset=wpStarry then T:=MeteorTime;
      A:=Render(T); SavePNG(A,Format('weather_%.2d.png',[Ord(Preset)]));
      B:=Render(T+0.5); D:=Render(T); Check(Same(A,D),'Integrated reverse seek failed');
      CSV.Add(Format('%d,%s,%.2f',[Ord(Preset),string(WEATHER_SCENE_NAMES[Preset]),T],TFormatSettings.Invariant));
    end;
    CSV.SaveToFile(ImageDirectory+'weather_presets.csv',TEncoding.UTF8);
  finally CSV.Free end;
  ConfigureWeather(wpRain); SceneTracks[stRain]^.Value:=23.4; SceneTracks[stHour]^.Value:=16.3;
  A:=Render(1.25); WeatherPresetItem^.Value:=Ord(wpSunny); B:=Render(1.25);
  Check(Same(A,B),'Preset selection reset user edits');
  Check((SceneTracks[stRain]^.Value=23.4) and (SceneTracks[stHour]^.Value=16.3),'Rendering reset scene values');
  Writeln('PASS: sunny defaults, 14 weather presets, groups, original blue sky, 24-hour cycle, continuity, cloudiness, precipitation, wind, independent bodies, opaque/faint rainbow, atmosphere, filters');
end;

procedure RunCloudFlowTests;
const Times: array[0..6] of Double = (0,30,90,180,600,3600,-180);
var A,B,Start: TPixels; T: Double; I,Direction: Integer; Delta: Int64;
  MainSession,FreshSession: Pointer;
begin
  Scene.Width:=320; Scene.Height:=180;
  IsolateWeather; SceneTracks[stOvercast]^.Value:=35; SceneTracks[stWindSpeed]^.Value:=10;
  Start:=Render(0);
  for T in Times do
  begin
    A:=Render(T);
    Check(Coverage(A)>Scene.Width*Scene.Height div 100,'Clouds disappeared during continuous flow');
    B:=Render(T+1/30); Delta:=0;
    for I:=0 to High(A) do Delta:=Delta+Abs(Integer(A[I].A)-Integer(B[I].A));
    Check(Delta/Length(A)<5,'Clouds pop during flow or new cloud entry');
  end;
  A:=Render(0); Check(Same(A,Start),'Cloud cache eviction changed reverse-seek output');
  A:=Render(600); MainSession:=Video.UserData; FreshSession:=Table^.Func_Create(4567);
  Check(FreshSession<>nil,'Fresh cloud session creation failed');
  try
    Video.UserData:=FreshSession; B:=Render(600);
    Check(Same(A,B),'Seeking directly to new clouds differs from continuous rendering');
  finally
    Video.UserData:=MainSession; Table^.Func_Destroy(4567,FreshSession);
  end;
  for Direction in [90,180,270] do
  begin
    SceneTracks[stWindDirection]^.Value:=Direction; A:=Render(600);
    Check(Coverage(A)>Scene.Width*Scene.Height div 100,'Clouds run out in another wind direction');
  end;
  Scene.Width:=960; Scene.Height:=540;
  Writeln('PASS: default wind, ongoing new clouds, entry continuity, hour-long flow, reverse seek, fresh-session seek, four wind directions');
end;

procedure RunTwilightTests;
const Boundaries: array[0..3] of Double = (4.75,7.25,16.75,19.25);
  Hours: array[0..5] of Double = (5.5,6,6.5,17.5,18,18.5);
var A,B: TPixels; I,J,Upper,Lower: Integer; H,Y,Radius: Double;
begin
  ConfigureWeather(wpNight); Check(SceneTracks[stOvercast]^.Value=30,'Night preset cloudiness is not 30');
  IsolateWeather; DrawSkyItem^.Value:=1;
  Upper:=(Scene.Height div 12)*Scene.Width+Scene.Width div 2;
  Lower:=(Scene.Height-3)*Scene.Width+Scene.Width div 2;
  for H in [6.0,18.0] do
  begin
    SceneTracks[stHour]^.Value:=H; A:=Render(1.25);
    Check((Integer(A[Lower].R)>Integer(A[Lower].B)+50) and
      (Integer(A[Lower].G)>Integer(A[Lower].B)+20),'Horizon lacks red/orange/yellow light');
    Check(Integer(A[Upper].B)>Integer(A[Upper].R)+20,'Upper twilight sky is not distinct from warm horizon');
    SceneTracks[stHour]^.Value:=H+24; B:=Render(1.25); Check(Same(A,B),'Twilight 24-hour wrap differs');
    SavePNG(A,Format('horizon_%.2d.png',[Round(H)]));
  end;
  for H in Boundaries do
  begin
    SceneTracks[stHour]^.Value:=H-0.001; A:=Render(1.25);
    SceneTracks[stHour]^.Value:=H+0.001; B:=Render(1.25);
    Check(MaxColorDelta(A,B)<=2,'Twilight effect window is discontinuous');
  end;
  for J:=0 to 1 do
  begin
    Scene.Width:=960*(J+1); Scene.Height:=540*(J+1);
    ConfigureWeather(wpSunset); Y:=SceneTracks[stSunY]^.Value; Radius:=SceneTracks[stSunSize]^.Value/2;
    Check(Abs(Scene.Height/2+Y+Radius-Scene.Height*0.98)<0.01,'Sunset preset does not use scene horizon');
    ConfigureWeather(wpDawn);
    Check(Abs(SceneTracks[stSunY]^.Value-Y)<0.01,'Dawn horizon placement differs from sunset');
  end;
  Scene.Width:=960; Scene.Height:=540;
  for I:=0 to High(Hours) do
  begin
    if Hours[I]<12 then ConfigureWeather(wpDawn) else ConfigureWeather(wpSunset);
    SceneTracks[stHour]^.Value:=Hours[I]; A:=Render(1.25);
    SavePNG(A,Format('twilight_%.2d.png',[I]));
    B:=Render(3.25); B:=Render(1.25); Check(Same(A,B),'Twilight reverse seek differs');
  end;
  // シーン情報がない編集コンテキストでは960x540の初期値へフォールバックする。
  Edit.Info:=nil; WeatherPresetItem^.Value:=Ord(wpSunset);
  WeatherApplyButton^.Callback2(@Edit,Pointer(1234),'天気演出:2','設定を反映');
  Check(Abs(SceneTracks[stSunY]^.Value-(540*0.48-50))<0.01,'Twilight no-info fallback failed');
  Writeln('PASS: night cloudiness 30, red/orange/yellow horizon, morning/evening continuity, scene-aware preset positions, wrap and reverse seek');
end;

procedure RunSolarGlowTests;
var A,B,D: TPixels; Probe,FarProbe,I: Integer; T: Double;
begin
  Scene.Width:=320; Scene.Height:=180;
  IsolateWeather; DrawSkyItem^.Value:=1; SceneTracks[stHour]^.Value:=18;
  SceneTracks[stSunSize]^.Value:=30; SceneTracks[stSunY]^.Value:=75;
  SceneTracks[stSunX]^.Value:=-70; A:=Render(1.25);
  SceneTracks[stSunTransparency]^.Value:=0; B:=Render(1.25);
  Probe:=165*Scene.Width+123; FarProbe:=165*Scene.Width+310;
  Check(Integer(B[Probe].G)>Integer(A[Probe].G)+10,'Low sun does not brighten surrounding background');
  Check(CompareMem(@A[FarProbe],@B[FarProbe],SizeOf(TPIXEL_RGBA)),'Sun glow changes distant background');
  SceneTracks[stSunX]^.Value:=70; D:=Render(1.25);
  Check(Integer(D[Probe].G)<Integer(B[Probe].G)-8,'Sun glow does not follow sun X');
  SceneTracks[stSunY]^.Value:=-45; D:=Render(1.25);
  Probe:=165*Scene.Width+230;
  Check(CompareMem(@A[Probe],@D[Probe],SizeOf(TPIXEL_RGBA)),'High sun still causes horizon bloom');
  SceneTracks[stSunY]^.Value:=75; SceneTracks[stWindSpeed]^.Value:=10;
  B:=Render(1.25); D:=Render(2.25); Check(Same(B,D),'Cached sky changes fixed solar bloom');
  Scene.Width:=960; Scene.Height:=540;
  for I:=0 to 1 do
  begin
    if I=0 then ConfigureWeather(wpDawn) else ConfigureWeather(wpSunset);
    SceneTracks[stOvercast]^.Value:=0; SceneTracks[stSunX]^.Value:=0;
    SceneTracks[stSunY]^.Value:=Scene.Height/2;
    T:=1.25; A:=Render(T); SavePNG(A,Format('solar_glow_%d.png',[I]));
  end;
  Writeln('PASS: localized horizon bloom, X/Y following, distant color preservation, cached-sky stability');
end;

procedure RunWeatherDetailTests;
var A,B: TPixels; I,LowVisible,HighVisible: Integer; T,FlashTime: Double;
begin
  Scene.Width:=320; Scene.Height:=180;
  ConfigureWeather(wpSunny); DrawSkyItem^.Value:=0; SceneTracks[stSunTransparency]^.Value:=100;
  A:=Render(1.25);
  ConfigureWeather(wpThinCloud); DrawSkyItem^.Value:=0; SceneTracks[stSunTransparency]^.Value:=100;
  B:=Render(1.25); Check(AlphaSum(B)>AlphaSum(A)*1.2,'Thin cloud preset does not differ from sunny');
  ConfigureWeather(wpCloudy); A:=Render(1.25); ConfigureWeather(wpRain); B:=Render(1.25);
  Check(MeanLight(A)>MeanLight(B)+5,'Cloudy preset is too close to dark rain weather');
  IsolateWeather; SceneTracks[stSnow]^.Value:=55; SceneTracks[stSnowSize]^.Value:=5; A:=Render(1.25);
  SceneTracks[stSnowSize]^.Value:=10; B:=Render(1.25);
  Check(Coverage(B)>Coverage(A)*1.8,'Snow size does not enlarge flakes');
  IsolateWeather; SceneTracks[stStars]^.Value:=85; SceneTracks[stStarSize]^.Value:=2.4; A:=Render(1.25);
  SceneTracks[stStarSize]^.Value:=4; B:=Render(1.25);
  Check(Coverage(B)>Coverage(A),'Star size has no effect');
  IsolateWeather; SceneTracks[stFog]^.Value:=85; A:=Render(1.25);
  Check(AlphaSum(A)>Int64(Length(A))*100,'Fog is too weak to form white haze');
  for I:=0 to High(A) do
    if A[I].A>10 then Check((Abs(Integer(A[I].R)-Integer(A[I].B))<=5) and
      (Abs(Integer(A[I].R)-Integer(A[I].G))<=5),'Day fog is colored rather than white haze');
  IsolateWeather; SceneTracks[stLightning]^.Value:=80;
  SceneTracks[stLightningWidth]^.Value:=0; SceneTracks[stLightningFlash]^.Value:=0;
  Check(Coverage(Render(1.25))=0,'Disabled lightning still draws');
  SceneTracks[stLightningFlash]^.Value:=100; FlashTime:=0;
  for I:=0 to 320 do
  begin
    T:=I*0.025; A:=Render(T);
    if AlphaSum(A)>Int64(Length(A))*80 then begin FlashTime:=T; Break end;
  end;
  Check(AlphaSum(A)>Int64(Length(A))*80,'Full-frame lightning flash never appears');
  for I:=0 to High(A) do Check(A[I].A=A[0].A,'Flash-only lightning does not light the whole frame');
  SavePNG(A,'lightning_full_frame.png');
  SceneTracks[stLightningFlash]^.Value:=0; SceneTracks[stLightningWidth]^.Value:=2; A:=Render(FlashTime);
  SceneTracks[stLightningWidth]^.Value:=14; B:=Render(FlashTime);
  Check(Coverage(B)>Coverage(A)*1.4,'Lightning width control is ineffective');
  SavePNG(B,'lightning_bold.png');
  ConfigureWeather(wpThunderstorm); SceneTracks[stLightningWidth]^.Value:=0;
  SceneTracks[stLightningFlash]^.Value:=100; SavePNG(Render(FlashTime),'thunderstorm_flash_only.png');
  ConfigureWeather(wpStarry);
  Check((SceneTracks[stMeteors]^.Value>0) and (SceneTracks[stMeteorFrequency]^.Value>0),
    'Starry preset does not enable meteors');
  IsolateWeather; SceneTracks[stMeteors]^.Value:=75; SceneTracks[stMeteorFrequency]^.Value:=12;
  for I:=0 to 120 do begin T:=I*0.05; A:=Render(T); if Coverage(A)>0 then Break end;
  Check(Coverage(A)>0,'Random meteor event is missing'); B:=Render(T+5);
  Check(not Same(A,B),'Meteors repeat the same event each interval');
  B:=Render(T); Check(Same(A,B),'Meteor reverse seek is not reproducible');
  SceneTracks[stMeteorFrequency]^.Value:=0; Check(Coverage(Render(T))=0,'Zero meteor frequency still draws');
  LowVisible:=0; HighVisible:=0;
  SceneTracks[stMeteorFrequency]^.Value:=3;
  for I:=0 to 149 do if Coverage(Render(I*0.2))>0 then Inc(LowVisible);
  SceneTracks[stMeteorFrequency]^.Value:=30;
  for I:=0 to 149 do if Coverage(Render(I*0.2))>0 then Inc(HighVisible);
  Check((HighVisible>0) and (HighVisible>LowVisible*2),'Meteor frequency does not increase event count');
  Scene.Width:=960; Scene.Height:=540;
  ConfigureWeather(wpSunny); A:=Render(1.25); SavePNG(A,'fog_background.png');
  HostInput:=Copy(A); Obj.Width:=Scene.Width; Obj.Height:=Scene.Height; Video.GetImageData:=GetImage;
  try
    ConfigureWeather(wpFog); DrawSkyItem^.Value:=0; B:=Render(1.25);
    Check(MeanLight(B)>MeanLight(A),'Fog does not add white haze over an image');
    SavePNG(B,'fog_overlay.png');
  finally
    HostInput:=nil; Obj.Width:=0; Obj.Height:=0; Video.GetImageData:=nil;
  end;
  Writeln('PASS: distinct thin/cloudy presets, larger snow/stars, white haze, bold lightning, full-frame flash, random meteor frequency and seek');
end;

procedure SaveCloudFlowPreview;
var I: Integer;
begin
  // 本番の初期値・シード1の動きを小さな確認画像として保存する。
  Scene.Width:=960; Scene.Height:=540;
  for I:=0 to 59 do SavePNG(Render(I*0.2),Format('flow_%.3d.png',[I]));
end;

procedure RunTests;
var Style: TWeatherStyle; A,B,D: TPixels; CSV: TStringList; Watch: TStopwatch;
  I,J,N,FullArea,HalfArea,ThinArea,Before: Integer; T: Double; OtherSession,MainSession: Pointer;
begin
  Tracks[wtSeed]^.Value:=17;
  CSV:=TStringList.Create;
  try
    CSV.Add('style,name,time,render_ms,visible_pixels');
    for Style:=Low(TWeatherStyle) to High(TWeatherStyle) do
    begin
      Configure(Style); T:=1.25;
      Watch:=TStopwatch.StartNew; A:=Render(T); Watch.Stop;
      if Style=wsMeteor then
        for J:=1 to 40 do
        begin
          if Coverage(A)>0 then Break;
          T:=J*0.1; A:=Render(T);
        end;
      N:=Coverage(A); Check(N>0,'Empty preset: '+string(WEATHER_STYLE_NAMES[Style]));
      SavePNG(A,Format('%.2d.png',[Ord(Style)]));
      CSV.Add(Format('%d,%s,%.2f,%.3f,%d',[Ord(Style),string(WEATHER_STYLE_NAMES[Style]),T,Watch.Elapsed.TotalMilliseconds,N],TFormatSettings.Invariant));
      D:=Render(T+0.65); B:=Render(T);
      Check(Same(A,B),'Reverse seek changed preset: '+string(WEATHER_STYLE_NAMES[Style]));
      if Style in [wsTwinklingStars,wsWhiteCloud,wsRain,wsSnow] then
        Check(not Same(A,D),'Animation is static');
      Obj.FrameTotal:=9999; B:=Render(T); Obj.FrameTotal:=150;
      Check(Same(A,B),'Duration changed motion');
    end;
    CSV.SaveToFile(ImageDirectory+'presets.csv',TEncoding.UTF8);
  finally CSV.Free end;
  Configure(wsFullMoon); A:=Render(0); FullArea:=Coverage(A);
  Configure(wsHalfMoon); A:=Render(0); HalfArea:=Coverage(A);
  Configure(wsThinCrescent); A:=Render(0); ThinArea:=Coverage(A);
  Check((FullArea>HalfArea) and (HalfArea>ThinArea),'Moon phases have wrong coverage');
  Configure(wsSunrise); Tracks[wtGlow]^.Value:=0; A:=Render(0);
  for J:=0 to Scene.Height div 2-1 do for I:=0 to Scene.Width-1 do
    Check(Abs(A[J*Scene.Width+I].A-A[(Scene.Height-1-J)*Scene.Width+I].A)<=1,'Sun was clipped by a horizon');
  Tracks[wtProgress]^.Value:=0; A:=Render(0); Tracks[wtProgress]^.Value:=100; B:=Render(0);
  Check(not Same(A,B),'Sun progress has no effect');
  Configure(wsSunsetSky); Tracks[wtProgress]^.Value:=0; A:=Render(0);
  Tracks[wtProgress]^.Value:=100; B:=Render(0); Check(not Same(A,B),'Sky progress has no effect');
  Configure(wsTwinklingStars); Tracks[wtSpeed]^.Value:=0; A:=Render(-2); B:=Render(3);
  Check(Same(A,B),'Zero speed is not stationary');
  Tracks[wtSeed]^.Value:=18; D:=Render(-2); Check(not Same(A,D),'Seed does not affect stars'); Tracks[wtSeed]^.Value:=17;
  Configure(wsSun); Tracks[wtSize]^.Value:=93.7; A:=Render(0); B:=Render(2);
  Check(Abs(Tracks[wtSize]^.Value-93.7)<1E-8,'Rendering reset a user adjustment');
  Obj.Width:=Scene.Width; Obj.Height:=Scene.Height; Video.GetImageData:=GetImage;
  SetLength(HostInput,Scene.Width*Scene.Height);
  for I:=0 to High(HostInput) do
  begin HostInput[I].R:=I mod 251; HostInput[I].G:=(I div 7) mod 251;
    HostInput[I].B:=83; HostInput[I].A:=I mod 256 end;
  Tracks[wtStrength]^.Value:=0; A:=Render(1); Check(Same(A,HostInput),'Zero strength modified RGBA');
  Tracks[wtStrength]^.Value:=100; A:=Render(1);
  Check(CompareMem(@A[0],@HostInput[0],SizeOf(TPIXEL_RGBA)),'Sun changed pixels outside support');
  for I:=0 to High(A) do Check(A[I].A>=HostInput[I].A,'Overlay reduced input alpha');
  SavePNG(A,'image_overlay.png');
  HostInput:=nil; Obj.Width:=0; Obj.Height:=0; Video.GetImageData:=nil;
  Configure(wsRain); A:=Render(-1.25); MainSession:=Video.UserData; OtherSession:=Table^.Func_Create(3456);
  Check(OtherSession<>nil,'Second instance creation failed');
  try
    Video.UserData:=OtherSession; B:=Render(23.5);
    Table^.Func_Destroy(3456,OtherSession); OtherSession:=nil;
  finally
    if OtherSession<>nil then Table^.Func_Destroy(3456,OtherSession);
    Video.UserData:=MainSession;
  end;
  B:=Render(-1.25); Check(Same(A,B),'Second instance changed original render state');
  Configure(wsWhiteCloud); Tracks[wtSpeed]^.Value:=2000;
  A:=Render(1E9); B:=Render(-1E9); Check((Length(A)>0) and (Length(B)>0),'Long-time rendering failed');
  Tracks[wtSize]^.Value:=NaN; A:=Render(0); Check(Coverage(A)=0,'Non-finite size was not sanitized');
  Writeln('PASS: 44 presets, reverse seek, animation, duration, phase, full sun, progress, seed, edits, RGBA, instances');
  Before:=SetCount; Scene.Width:=0; Scene.Height:=0;
  Check(Table^.Func_Proc_Video(@Video)=0,'Invalid dimensions accepted');
  Check(SetCount=Before,'Invalid dimensions wrote an image');
  Scene.Width:=8192; Scene.Height:=8192;
  Check(Table^.Func_Proc_Video(@Video)=0,'Pixel limit not enforced');
  Scene.Width:=960; Scene.Height:=540;
  Check(Table^.Func_Proc_Video(nil)=0,'Nil video accepted');
end;

procedure RunProfile;
const Names: array[0..9] of string = ('sunny','sky','sun','cloud_static','cloud_wind',
  'rain','snow_5px','snow_10px','fog','stars');
var K,I,J: Integer; Watch: TStopwatch; V: array[0..4] of Double; Temp,First: Double;
  CSV: TStringList; Pixels: TPixels;
begin
  Tracks[wtSeed]^.Value:=17; Scene.Width:=1920; Scene.Height:=1080;
  CSV:=TStringList.Create;
  try
    CSV.Add('component,width,height,frames,median_ms,min_ms,max_ms,first_ms');
    for K:=0 to High(Names) do
    begin
      IsolateWeather;
      case K of
        0: ConfigureWeather(wpSunny);
        1: DrawSkyItem^.Value:=1;
        2: SceneTracks[stSunTransparency]^.Value:=0;
        3,4: begin SceneTracks[stOvercast]^.Value:=35;
          if K=4 then SceneTracks[stWindSpeed]^.Value:=10 end;
        5: SceneTracks[stRain]^.Value:=45;
        6,7: begin SceneTracks[stSnow]^.Value:=55;
          SceneTracks[stSnowSize]^.Value:=5+(K-6)*5 end;
        8: begin SceneTracks[stFog]^.Value:=85; SceneTracks[stWindSpeed]^.Value:=10 end;
        9: begin SceneTracks[stStars]^.Value:=85; SceneTracks[stStarSize]^.Value:=2.4 end;
      end;
      Watch:=TStopwatch.StartNew; Pixels:=Render(1.25); Watch.Stop; First:=Watch.Elapsed.TotalMilliseconds;
      for I:=0 to High(V) do
      begin
        Watch:=TStopwatch.StartNew; Pixels:=Render(1.25+I/30); Watch.Stop;
        V[I]:=Watch.Elapsed.TotalMilliseconds;
      end;
      for I:=0 to High(V)-1 do for J:=I+1 to High(V) do
        if V[I]>V[J] then begin Temp:=V[I]; V[I]:=V[J]; V[J]:=Temp end;
      CSV.Add(Format('%s,1920,1080,5,%.3f,%.3f,%.3f,%.3f',
        [Names[K],V[2],V[0],V[4],First],TFormatSettings.Invariant));
      Check(Length(Pixels)=Scene.Width*Scene.Height,'Profile frame size mismatch');
    end;
    CSV.SaveToFile(ImageDirectory+'profile1080.csv',TEncoding.UTF8);
    Writeln('PASS: component profile saved');
  finally CSV.Free end;
end;

procedure RunBenchmark;
const Styles: array[0..9] of TWeatherStyle = (wsSun,wsSunlight,wsRays,wsFullMoon,
  wsBlueSky,wsTwinklingStars,wsWhiteCloud,wsRain,wsSnow,wsDoubleRainbow);
  ScenePresets: array[0..7] of TWeatherScenePreset = (wpSunny,wpClear,wpCloudy,wpRain,wpDownpour,wpBlizzard,wpNight,wpFog);
var Style: TWeatherStyle; Preset: TWeatherScenePreset; I,J: Integer; Watch: TStopwatch; Values: array[0..4] of Double;
  Temp,FirstMs: Double; CSV: TStringList; Pixels: TPixels; MainSession,ColdSession: Pointer;
begin
  Scene.Width:=1920; Scene.Height:=1080;
  CSV:=TStringList.Create;
  try
    CSV.Add('name,width,height,warmup,frames,median_ms,min_ms,max_ms');
    for Style in Styles do
    begin
      Configure(Style); Pixels:=Render(1.25);
      for I:=0 to High(Values) do
      begin
        Watch:=TStopwatch.StartNew; Pixels:=Render(1.25+I/30); Watch.Stop;
        Values[I]:=Watch.Elapsed.TotalMilliseconds;
      end;
      for I:=0 to High(Values)-1 do for J:=I+1 to High(Values) do
        if Values[I]>Values[J] then begin Temp:=Values[I]; Values[I]:=Values[J]; Values[J]:=Temp end;
      CSV.Add(Format('%s,1920,1080,1,5,%.3f,%.3f,%.3f',
        [string(WEATHER_STYLE_NAMES[Style]),Values[2],Values[0],Values[4]],TFormatSettings.Invariant));
      Check(Length(Pixels)=Scene.Width*Scene.Height,'Benchmark output size mismatch');
    end;
    CSV.SaveToFile(ImageDirectory+'benchmark1080.csv',TEncoding.UTF8);
    CSV.Clear; CSV.Add('name,width,height,warmup,frames,median_ms,min_ms,max_ms,first_ms');
    MainSession:=Video.UserData; ColdSession:=Table^.Func_Create(2345);
    Check(ColdSession<>nil,'Benchmark session creation failed');
    Video.UserData:=ColdSession;
    try
    for Preset in ScenePresets do
    begin
      ConfigureWeather(Preset); Watch:=TStopwatch.StartNew; Pixels:=Render(1.25); Watch.Stop;
      FirstMs:=Watch.Elapsed.TotalMilliseconds;
      for I:=0 to High(Values) do
      begin
        Watch:=TStopwatch.StartNew; Pixels:=Render(1.25+I/30); Watch.Stop;
        Values[I]:=Watch.Elapsed.TotalMilliseconds;
      end;
      for I:=0 to High(Values)-1 do for J:=I+1 to High(Values) do
        if Values[I]>Values[J] then begin Temp:=Values[I]; Values[I]:=Values[J]; Values[J]:=Temp end;
      CSV.Add(Format('%s,1920,1080,1,5,%.3f,%.3f,%.3f,%.3f',
        [string(WEATHER_SCENE_NAMES[Preset]),Values[2],Values[0],Values[4],FirstMs],TFormatSettings.Invariant));
    end;
    CSV.SaveToFile(ImageDirectory+'weather_benchmark1080.csv',TEncoding.UTF8);
    finally
      Video.UserData:=MainSession;
      Table^.Func_Destroy(2345,ColdSession);
    end;
  finally CSV.Free end;
end;

var Module: HMODULE; Initialize: TInitialize; Required: TRequired;
  Uninitialize: TUninitialize; GetTable: TGetTable; Session: Pointer;
  PreviewWatch: TStopwatch; PreviewPixels: TPixels;
begin
  try
    Check((ParamCount=2) or (ParamCount=3),'Usage: WeatherFX_RenderTests <AUF2> <image directory> [--benchmark | --preview-default | --preview-flow]');
    ImageDirectory:=IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(2)));
    ForceDirectories(ImageDirectory);
    Module:=LoadLibrary(PChar(ExpandFileName(ParamStr(1)))); Check(Module<>0,'AUF2 load failed');
    try
      Initialize:=TInitialize(GetProcAddress(Module,'InitializePlugin'));
      Required:=TRequired(GetProcAddress(Module,'RequiredVersion'));
      Uninitialize:=TUninitialize(GetProcAddress(Module,'UninitializePlugin'));
      GetTable:=TGetTable(GetProcAddress(Module,'GetFilterPluginTable'));
      Check(Assigned(Initialize) and Assigned(Required) and Assigned(Uninitialize) and Assigned(GetTable),'Missing export');
      Check(Required()=2011600,'Version requirement changed');
      Check(Initialize(Required()-1)=0,'Unsupported host accepted');
      Check(Initialize(Required())=1,'Initialization failed');
      Table:=GetTable(); Check(Table<>nil,'No table');
      Check(string(Table^.Name)='天気演出','Wrong plugin name');
      Check(string(Table^.Label_)='SYNC','Wrong group');
      Check(Table^.Flag=(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA),
        'Standalone filter registration flags mismatch');
      Check((Table^.Flag and FILTER_FLAG_INPUT)=0,'Filter registered as media input');
      Check((Table^.Flag and 32)=0,'Plugin is hidden from add menus');
      BindItems;
      Edit:=Default(TEDIT_SECTION); Edit.SetObjectItemValue:=SetItemValue; EditTargetCorrect:=True;
      Scene:=Default(TSCENE_INFO); Scene.Width:=960; Scene.Height:=540; Scene.Rate:=30; Scene.Scale:=1;
      Obj:=Default(TOBJECT_INFO); Obj.FrameTotal:=150; Obj.Flag:=OBJECT_FLAG_FILTER_OBJECT;
      Video:=Default(TFILTER_PROC_VIDEO); Video.Scene:=@Scene; Video.Object_:=@Obj; Video.SetImageData:=SetImage;
      Session:=Table^.Func_Create(1234); Check(Session<>nil,'Session creation failed');
      try
        Video.UserData:=Session;
        if (ParamCount=3) and (ParamStr(3)='--preview-default') then
        begin
          PreviewWatch:=TStopwatch.StartNew; PreviewPixels:=Render(1.25); PreviewWatch.Stop;
          SavePNG(PreviewPixels,'new_sunny.png');
          Writeln(Format('Default first render 960x540: %.3f ms',[PreviewWatch.Elapsed.TotalMilliseconds],TFormatSettings.Invariant));
        end
        else if (ParamCount=3) and (ParamStr(3)='--preview-flow') then SaveCloudFlowPreview
        else if (ParamCount=3) and (ParamStr(3)='--profile') then RunProfile
        else
        begin
          RunIntegratedTests;
          RunCloudFlowTests;
          RunTwilightTests;
          RunSolarGlowTests;
          RunWeatherDetailTests;
          RunTests;
          Video.UserData:=Session;
          Configure(wsRain);
          Check(Coverage(Render(-1.25))>0,'Original instance no longer works');
          if (ParamCount=3) and (ParamStr(3)='--benchmark') then RunBenchmark;
        end;
      finally Table^.Func_Destroy(1234,Session) end;
      Uninitialize;
    finally FreeLibrary(Module) end;
  except
    on E: Exception do begin Writeln(ErrOutput,E.ClassName+': '+E.Message); ExitCode:=1 end;
  end;
end.
