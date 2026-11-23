unit WeatherFX_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 天気プリセットと各現象の折りたたみ項目を登録する。
// 初期値の再適用は設定ボタンの編集APIで行い、描画中に値を書き換えない。

interface

uses WeatherFX_SceneSettings;

// DLL所有の項目を登録する。登録後の現在値はホストが更新する。
procedure RegisterWeatherFXParameters;
// 呼出時の現在値を独立した設定へコピーする。描画中に保存値とGUIを変更しない。
function ReadWeatherSceneSettings: TWeatherSceneSettings;

implementation

uses System.Math, System.SysUtils, Winapi.Windows, AviUtl2FilterTypes, PluginFilterTable, WeatherFX_Settings;

var
  ScenePresetItem: TFILTER_ITEM_SELECT;
  SceneOptions: array[0..WEATHER_SCENE_PRESET_COUNT] of TFILTER_ITEM_SELECT_ITEM;
  SeedTrack: TFILTER_ITEM_TRACK;
  SceneTracks: array[TWeatherSceneTrack] of TFILTER_ITEM_TRACK;
  SceneButton: TFILTER_ITEM_BUTTON;
  DrawSkyItem,DoubleRainbowItem: TFILTER_ITEM_CHECK;
  Groups,GroupEnds: array[0..6] of TFILTER_ITEM_GROUP;

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
    SetItem(DrawSkyItem.Name,UTF8String(IntToStr(Ord(S.DrawSky))));
    DrawSkyItem.Value:=Ord(S.DrawSky);
    SetItem(DoubleRainbowItem.Name,UTF8String(IntToStr(Ord(S.DoubleRainbow))));
    DoubleRainbowItem.Value:=Ord(S.DoubleRainbow);
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
  if Index=6 then AddTrack(SeedTrack,WEATHER_TRACKS[wtSeed].Name,S.Seed,
    WEATHER_TRACKS[wtSeed].MinValue,WEATHER_TRACKS[wtSeed].MaxValue,WEATHER_TRACKS[wtSeed].Step);
  AddGroup(GroupEnds[Index],'',0);
end;

procedure RegisterWeatherFXParameters;
var I: Integer; Scene: TWeatherSceneSettings;
begin
  Scene:=WeatherScenePreset(wpSunny);
  FillChar(SceneOptions,SizeOf(SceneOptions),0);
  for I:=0 to WEATHER_SCENE_PRESET_COUNT-1 do
  begin SceneOptions[I].Name:=WEATHER_SCENE_NAMES[TWeatherScenePreset(I)]; SceneOptions[I].Value:=I end;
  AddSelect(ScenePresetItem,'天気プリセット',Ord(wpSunny),@SceneOptions[0]);
  AddButton(SceneButton,'設定を反映',ApplyScenePreset);
  AddSceneGroup(0,'基本設定',stHour,stOvercast,1,Scene);
  AddSceneGroup(1,'雨・雪',stRain,stFallSpeed,0,Scene);
  AddSceneGroup(2,'風',stWindSpeed,stWindExpression,0,Scene);
  AddSceneGroup(3,'太陽',stSunX,stSunStrength,0,Scene);
  AddSceneGroup(4,'月',stMoonX,stMoonDirection,0,Scene);
  AddSceneGroup(5,'虹',stRainbowX,stRainbowTransparency,0,Scene);
  AddSceneGroup(6,'その他の天候',stLightning,stMoonlight,0,Scene);
end;

function ReadWeatherSceneSettings: TWeatherSceneSettings;
var Track: TWeatherSceneTrack;
begin
  Result:=WeatherScenePreset(wpSunny);
  for Track:=Low(TWeatherSceneTrack) to High(TWeatherSceneTrack) do
    Result.Values[Track]:=ClampSceneTrack(Track,SceneTracks[Track].Value);
  Result.DrawSky:=DrawSkyItem.Value<>0; Result.DoubleRainbow:=DoubleRainbowItem.Value<>0;
  Result.Seed:=Round(WeatherClampTrack(wtSeed,SeedTrack.Value));
end;

end.
