unit WeatherFX_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 統合天気のプリセット・折りたたみ項目と従来の個別演出を登録する。
// 初期値の再適用は設定ボタンの編集APIで行い、描画中に値を書き換えない。

interface

uses WeatherFX_Settings, WeatherFX_SceneSettings;

// DLL所有の項目を登録する。登録後の現在値はホストが更新する。
procedure RegisterWeatherFXParameters;
// 呼出時の現在値を独立した設定へコピーする。描画中に保存値とGUIを変更しない。
function ReadWeatherFXSettings: TWeatherSettings;
function ReadWeatherSceneSettings: TWeatherSceneSettings;
function ReadWeatherRenderMode: TWeatherRenderMode;

implementation

uses System.Math, System.SysUtils, Winapi.Windows, AviUtl2FilterTypes, PluginFilterTable;

var
  StyleItem: TFILTER_ITEM_SELECT;
  StyleOptions: array[0..WEATHER_STYLE_COUNT] of TFILTER_ITEM_SELECT_ITEM;
  Tracks: array[TWeatherTrack] of TFILTER_ITEM_TRACK;
  ApplyButton: TFILTER_ITEM_BUTTON;
  ColorItem: TFILTER_ITEM_COLOR;
  CustomColor: TFILTER_ITEM_CHECK;
  ScenePresetItem,ModeItem: TFILTER_ITEM_SELECT;
  SceneOptions: array[0..WEATHER_SCENE_PRESET_COUNT] of TFILTER_ITEM_SELECT_ITEM;
  ModeOptions: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  SceneTracks: array[TWeatherSceneTrack] of TFILTER_ITEM_TRACK;
  SceneButton: TFILTER_ITEM_BUTTON;
  DrawSkyItem,DoubleRainbowItem: TFILTER_ITEM_CHECK;
  Groups,GroupEnds: array[0..7] of TFILTER_ITEM_GROUP;

procedure ApplyPreset(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect,Item: PWideChar); cdecl;
var S: TWeatherSettings; Track: TWeatherTrack; Target: string;
  procedure SetItem(Name: PWideChar; const Text: UTF8String);
  begin
    if not Edit^.SetObjectItemValue(Obj,PWideChar(Target),Name,PAnsiChar(Text)) then
      raise EInvalidOp.CreateFmt('Could not apply weather preset item: %s',[string(Name)]);
  end;
begin
  if (Edit=nil) or (Obj=nil) or (Effect=nil) then Exit;
  if not Assigned(Edit^.SetObjectItemValue) then Exit;
  try
    Target:=Effect;
    S:=WeatherPreset(TWeatherStyle(EnsureRange(StyleItem.Value,0,WEATHER_STYLE_COUNT-1)));
    for Track:=Low(TWeatherTrack) to High(TWeatherTrack) do
    begin
      // 乱数の再現条件はユーザーが設定した値を維持する。
      if Track=wtSeed then Continue;
      SetItem(Tracks[Track].Name,UTF8String(FloatToStr(S.Values[Track],TFormatSettings.Invariant)));
      Tracks[Track].Value:=S.Values[Track];
    end;
    SetItem(ColorItem.Name,UTF8String(IntToHex(S.ColorRGB,6)));
    ColorItem.R:=Byte((S.ColorRGB shr 16) and 255);
    ColorItem.G:=Byte((S.ColorRGB shr 8) and 255); ColorItem.B:=Byte(S.ColorRGB and 255);
    SetItem(CustomColor.Name,'0'); CustomColor.Value:=0;
    SetItem(ModeItem.Name,'個別演出'); ModeItem.Value:=Ord(wmIndividual);
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_WeatherFX preset: '+E.Message));
  end;
end;

procedure ApplyScenePreset(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect,Item: PWideChar); cdecl;
var S: TWeatherSceneSettings; Track: TWeatherSceneTrack; Target: string;
  Preset: TWeatherScenePreset; Info: PEDIT_INFO;
  procedure SetItem(Name: PWideChar; const Text: UTF8String);
  begin
    if not Edit^.SetObjectItemValue(Obj,PWideChar(Target),Name,PAnsiChar(Text)) then
      raise EInvalidOp.CreateFmt('Could not apply integrated weather item: %s',[string(Name)]);
  end;
begin
  if (Edit=nil) or (Obj=nil) or (Effect=nil) then Exit;
  if not Assigned(Edit^.SetObjectItemValue) then Exit;
  try
    Target:=Effect;
    Preset:=TWeatherScenePreset(EnsureRange(ScenePresetItem.Value,0,WEATHER_SCENE_PRESET_COUNT-1));
    S:=WeatherScenePreset(Preset);
    // SDKのEDIT_SECTION.infoはコールバック中だけ参照できるEDIT_INFOへのポインター。
    if Edit^.Info<>nil then
    begin
      Info:=PEDIT_INFO(Edit^.Info);
      if (Info^.Width>0) and (Info^.Height>0) then
        S:=WeatherScenePreset(Preset,Info^.Width,Info^.Height);
    end;
    for Track:=Low(TWeatherSceneTrack) to High(TWeatherSceneTrack) do
    begin
      SetItem(SceneTracks[Track].Name,UTF8String(FloatToStr(S.Values[Track],TFormatSettings.Invariant)));
      SceneTracks[Track].Value:=S.Values[Track];
    end;
    SetItem(DrawSkyItem.Name,'1'); DrawSkyItem.Value:=1;
    SetItem(DoubleRainbowItem.Name,'0'); DoubleRainbowItem.Value:=0;
    SetItem(ModeItem.Name,'統合天気'); ModeItem.Value:=Ord(wmIntegrated);
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_WeatherFX weather preset: '+E.Message));
  end;
end;

procedure AddSceneGroup(Index: Integer; Name: PWideChar;
  First,Last: TWeatherSceneTrack; Visible: Byte; const S: TWeatherSceneSettings);
var Track: TWeatherSceneTrack;
begin
  AddGroup(Groups[Index],Name,Visible);
  for Track:=First to Last do
    AddTrack(SceneTracks[Track],WEATHER_SCENE_TRACKS[Track].Name,S.Values[Track],
      WEATHER_SCENE_TRACKS[Track].MinValue,WEATHER_SCENE_TRACKS[Track].MaxValue,WEATHER_SCENE_TRACKS[Track].Step);
  if Index=0 then AddCheck(DrawSkyItem,'空を描画',1);
  if Index=5 then AddCheck(DoubleRainbowItem,'二重虹',0);
  if Index=6 then AddTrack(Tracks[wtSeed],'シード',1,0,1000000,1);
  AddGroup(GroupEnds[Index],'',0);
end;

procedure RegisterWeatherFXParameters;
var I: Integer; Track: TWeatherTrack; S: TWeatherSettings; Scene: TWeatherSceneSettings;
begin
  S:=WeatherPreset(wsSun);
  Scene:=WeatherScenePreset(wpSunny);
  FillChar(SceneOptions,SizeOf(SceneOptions),0);
  for I:=0 to WEATHER_SCENE_PRESET_COUNT-1 do
  begin SceneOptions[I].Name:=WEATHER_SCENE_NAMES[TWeatherScenePreset(I)]; SceneOptions[I].Value:=I end;
  AddSelect(ScenePresetItem,'天気プリセット',Ord(wpSunny),@SceneOptions[0]);
  AddButton(SceneButton,'設定を反映',ApplyScenePreset);
  FillChar(ModeOptions,SizeOf(ModeOptions),0);
  ModeOptions[0].Name:='統合天気'; ModeOptions[0].Value:=Ord(wmIntegrated);
  ModeOptions[1].Name:='個別演出'; ModeOptions[1].Value:=Ord(wmIndividual);
  AddSelect(ModeItem,'描画方式',Ord(wmIntegrated),@ModeOptions[0]);
  AddSceneGroup(0,'基本設定',stHour,stOvercast,1,Scene);
  AddSceneGroup(1,'雨・雪',stRain,stFallSpeed,0,Scene);
  AddSceneGroup(2,'風',stWindSpeed,stWindExpression,0,Scene);
  AddSceneGroup(3,'太陽',stSunX,stSunTransparency,0,Scene);
  AddSceneGroup(4,'月',stMoonX,stMoonDirection,0,Scene);
  AddSceneGroup(5,'虹',stRainbowX,stRainbowTransparency,0,Scene);
  AddSceneGroup(6,'その他の天候',stLightning,stMoonlight,0,Scene);
  AddGroup(Groups[7],'個別演出（従来）',0);
  FillChar(StyleOptions,SizeOf(StyleOptions),0);
  for I:=0 to WEATHER_STYLE_COUNT-1 do
  begin StyleOptions[I].Name:=WEATHER_STYLE_NAMES[TWeatherStyle(I)]; StyleOptions[I].Value:=I end;
  AddSelect(StyleItem,'スタイル',Ord(wsSun),@StyleOptions[0]);
  AddButton(ApplyButton,'設定',ApplyPreset);
  for Track:=Low(TWeatherTrack) to High(TWeatherTrack) do
    if Track<>wtSeed then
      AddTrack(Tracks[Track],WEATHER_TRACKS[Track].Name,S.Values[Track],
        WEATHER_TRACKS[Track].MinValue,WEATHER_TRACKS[Track].MaxValue,WEATHER_TRACKS[Track].Step);
  AddCheck(CustomColor,'色を指定',0);
  AddColor(ColorItem,'色',Byte(S.ColorRGB and 255),Byte((S.ColorRGB shr 8) and 255),
    Byte((S.ColorRGB shr 16) and 255));
  AddGroup(GroupEnds[7],'',0);
end;

function ReadWeatherSceneSettings: TWeatherSceneSettings;
var Track: TWeatherSceneTrack;
begin
  Result:=WeatherScenePreset(wpSunny);
  for Track:=Low(TWeatherSceneTrack) to High(TWeatherSceneTrack) do
    Result.Values[Track]:=ClampSceneTrack(Track,SceneTracks[Track].Value);
  Result.DrawSky:=DrawSkyItem.Value<>0; Result.DoubleRainbow:=DoubleRainbowItem.Value<>0;
  Result.Seed:=Round(WeatherClampTrack(wtSeed,Tracks[wtSeed].Value));
end;

function ReadWeatherRenderMode: TWeatherRenderMode;
begin Result:=TWeatherRenderMode(EnsureRange(ModeItem.Value,Ord(wmIntegrated),Ord(wmIndividual))) end;

function ReadWeatherFXSettings: TWeatherSettings;
var Track: TWeatherTrack;
begin
  Result:=WeatherPreset(TWeatherStyle(EnsureRange(StyleItem.Value,0,WEATHER_STYLE_COUNT-1)));
  for Track:=Low(TWeatherTrack) to High(TWeatherTrack) do
    Result.Values[Track]:=WeatherClampTrack(Track,Tracks[Track].Value);
  if CustomColor.Value<>0 then
    Result.ColorRGB:=(Cardinal(ColorItem.R) shl 16) or (Cardinal(ColorItem.G) shl 8) or ColorItem.B;
end;

end.
