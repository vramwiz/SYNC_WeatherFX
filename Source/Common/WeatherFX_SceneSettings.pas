unit WeatherFX_SceneSettings;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 統合天気の保存項目とプリセット。プリセット番号は描画器へ渡さず、現在値だけで描画する。

interface

type
  TWeatherScenePreset = (wpSunny, wpClear, wpThinCloud, wpCloudy, wpRain,
    wpDownpour, wpSnow, wpBlizzard, wpThunderstorm, wpDawn, wpSunset,
    wpNight, wpStarry, wpFog, wpRainbow, wpAurora, wpMidsummer);
  TWeatherSceneTrack = (stHour, stOvercast,
    stRain, stSnow, stRainSize, stSnowSize, stFallSpeed,
    stWindSpeed, stWindDirection, stWindExpression,
    stSunX, stSunY, stSunSize, stSunTransparency, stSunStrength,
    stMoonX, stMoonY, stMoonSize, stMoonTransparency, stMoonPhase, stMoonDirection,
    stRainbowX, stRainbowY, stRainbowRadius, stRainbowArc, stRainbowWidth, stRainbowTransparency,
    stLightning, stLightningWidth, stLightningFlash, stFog, stAurora, stHeatHaze, stMirage,
    stStars, stStarSize, stMeteors, stMeteorFrequency,
    stSunlight, stMoonlight);
  TSceneTrackDefinition = record
    Name: PWideChar;
    MinValue, MaxValue, Step: Double;
  end;
  TWeatherSceneSettings = record
    Values: array[TWeatherSceneTrack] of Double;
    DrawSky, DoubleRainbow: Boolean;
    Seed: Integer;
  end;

const
  WEATHER_SCENE_PRESET_COUNT = Ord(High(TWeatherScenePreset))+1;
  WEATHER_SCENE_NAMES: array[TWeatherScenePreset] of PWideChar = (
    '晴れ', '快晴', '薄曇り', '曇り', '雨', '豪雨', '雪', '吹雪',
    '雷雨', '朝焼け', '夕焼け', '夜', '星空', '霧', '虹', 'オーロラ', '真夏');
  WEATHER_SCENE_TRACKS: array[TWeatherSceneTrack] of TSceneTrackDefinition = (
    (Name:'時刻'; MinValue:0; MaxValue:240; Step:0.01),
    (Name:'曇り具合'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'雨量'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'雪量'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'雨粒サイズ'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'雪片サイズ'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'落下速度'; MinValue:0; MaxValue:300; Step:0.1),
    (Name:'風速'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'風向'; MinValue:0; MaxValue:360; Step:0.1),
    (Name:'風表現の強さ'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'太陽X'; MinValue:-100000; MaxValue:100000; Step:0.01),
    (Name:'太陽Y'; MinValue:-100000; MaxValue:100000; Step:0.01),
    (Name:'太陽サイズ'; MinValue:0; MaxValue:20000; Step:0.1),
    (Name:'太陽透明度'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'太陽の強さ'; MinValue:0; MaxValue:200; Step:0.1),
    (Name:'月X'; MinValue:-100000; MaxValue:100000; Step:0.01),
    (Name:'月Y'; MinValue:-100000; MaxValue:100000; Step:0.01),
    (Name:'月サイズ'; MinValue:0; MaxValue:20000; Step:0.1),
    (Name:'月透明度'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'満ち欠け'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'欠ける方向'; MinValue:0; MaxValue:360; Step:0.1),
    (Name:'虹X'; MinValue:-100000; MaxValue:100000; Step:0.01),
    (Name:'虹Y'; MinValue:-100000; MaxValue:100000; Step:0.01),
    (Name:'円弧半径'; MinValue:0; MaxValue:20000; Step:0.1),
    (Name:'円弧角度'; MinValue:0; MaxValue:360; Step:0.1),
    (Name:'帯幅'; MinValue:0; MaxValue:2000; Step:0.1),
    (Name:'虹透明度'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'雷'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'雷線の太さ'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'雷の全面発光'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'霧'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'オーロラ'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'陽炎'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'蜃気楼'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'星'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'星サイズ'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'流れ星'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'流れ星頻度（回/分）'; MinValue:0; MaxValue:120; Step:0.1),
    (Name:'日差し'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'月明かり'; MinValue:0; MaxValue:100; Step:0.1));

// 新規配置と「設定を反映」で使う独立した値の集合。選択するだけでは呼び出さない。
function WeatherScenePreset(Preset: TWeatherScenePreset;
  SceneWidth: Integer = 960; SceneHeight: Integer = 540): TWeatherSceneSettings;
function ClampSceneTrack(Track: TWeatherSceneTrack; Value: Double): Double;

implementation

uses System.Math;

function ClampSceneTrack(Track: TWeatherSceneTrack; Value: Double): Double;
begin
  if IsNan(Value) or IsInfinite(Value) then Value:=0;
  Result:=EnsureRange(Value,WEATHER_SCENE_TRACKS[Track].MinValue,WEATHER_SCENE_TRACKS[Track].MaxValue);
end;

function WeatherScenePreset(Preset: TWeatherScenePreset; SceneWidth,SceneHeight: Integer): TWeatherSceneSettings;
begin
  SceneWidth:=EnsureRange(SceneWidth,1,8192);
  SceneHeight:=EnsureRange(SceneHeight,1,8192);
  Result:=Default(TWeatherSceneSettings);
  Result.DrawSky:=True; Result.Seed:=1;
  Result.Values[stHour]:=12; Result.Values[stOvercast]:=20;
  Result.Values[stRainSize]:=1.4; Result.Values[stSnowSize]:=5;
  Result.Values[stFallSpeed]:=100;
  Result.Values[stSunStrength]:=100;
  Result.Values[stSunX]:=-250; Result.Values[stSunY]:=-140; Result.Values[stSunSize]:=100;
  Result.Values[stMoonX]:=240; Result.Values[stMoonY]:=-140; Result.Values[stMoonSize]:=110;
  Result.Values[stMoonTransparency]:=100; Result.Values[stMoonPhase]:=100;
  Result.Values[stRainbowY]:=180; Result.Values[stRainbowRadius]:=400;
  Result.Values[stRainbowArc]:=160; Result.Values[stRainbowWidth]:=24;
  Result.Values[stRainbowTransparency]:=100;
  Result.Values[stLightningWidth]:=8; Result.Values[stLightningFlash]:=45;
  Result.Values[stStarSize]:=3.6; Result.Values[stMeteorFrequency]:=12;
  case Preset of
    wpSunny:
      begin
        Result.Values[stHour]:=11;
        Result.Values[stOvercast]:=35;
        Result.Values[stSunY]:=-200;
        Result.Values[stSunX]:=160;
        Result.Values[stSunSize]:=64;
        Result.Values[stWindSpeed]:=10;
      end;
    wpClear: Result.Values[stOvercast]:=0;
    wpThinCloud: begin Result.Values[stOvercast]:=55; Result.Values[stHour]:=11;
      Result.Values[stSunX]:=160; Result.Values[stSunY]:=-200; Result.Values[stSunSize]:=64;
      Result.Values[stSunTransparency]:=25; Result.Values[stWindSpeed]:=10 end;
    wpCloudy: begin Result.Values[stOvercast]:=68; Result.Values[stSunTransparency]:=55 end;
    wpRain: begin Result.Values[stOvercast]:=80; Result.Values[stRain]:=45;
      Result.Values[stSunTransparency]:=100; Result.Values[stWindSpeed]:=15 end;
    wpDownpour,wpThunderstorm:
      begin
        Result.Values[stOvercast]:=100; Result.Values[stRain]:=100;
        Result.Values[stSunTransparency]:=100; Result.Values[stWindSpeed]:=55;
        Result.Values[stWindDirection]:=180;
        if Preset=wpThunderstorm then begin Result.Values[stLightning]:=80;
          Result.Values[stLightningWidth]:=14; Result.Values[stLightningFlash]:=75 end;
      end;
    wpSnow: begin Result.Values[stOvercast]:=75; Result.Values[stSnow]:=55;
      Result.Values[stSnowSize]:=10;
      Result.Values[stSunTransparency]:=100; Result.Values[stWindSpeed]:=8 end;
    wpBlizzard: begin Result.Values[stOvercast]:=95; Result.Values[stSnow]:=100;
      Result.Values[stSnowSize]:=14;
      Result.Values[stWindSpeed]:=85; Result.Values[stWindDirection]:=180;
      Result.Values[stWindExpression]:=18; Result.Values[stSunTransparency]:=100 end;
    wpDawn: begin Result.Values[stHour]:=6; Result.Values[stOvercast]:=30 end;
    wpSunset: begin Result.Values[stHour]:=18; Result.Values[stOvercast]:=30 end;
    wpNight,wpStarry:
      begin
        Result.Values[stHour]:=0; Result.Values[stSunTransparency]:=100;
        Result.Values[stMoonTransparency]:=0;
        if Preset=wpStarry then begin Result.Values[stOvercast]:=0; Result.Values[stStars]:=85;
          Result.Values[stStarSize]:=4; Result.Values[stMeteors]:=75 end
        else begin Result.Values[stOvercast]:=30; Result.Values[stStars]:=20 end;
      end;
    wpFog: begin Result.Values[stHour]:=12; Result.Values[stOvercast]:=0;
      Result.Values[stFog]:=85; Result.Values[stSunTransparency]:=100;
      Result.Values[stWindSpeed]:=5 end;
    wpRainbow:
      begin
        Result.Values[stHour]:=15;
        Result.Values[stOvercast]:=13;
        Result.Values[stSunTransparency]:=100;
        // 虹の頂点と両側が、縦長・横長のどちらでも画面に収まるようにする。
        Result.Values[stRainbowRadius]:=Min(SceneWidth*0.43,SceneHeight*0.75);
        Result.Values[stRainbowY]:=Result.Values[stRainbowRadius]-SceneHeight*0.42;
        Result.Values[stRainbowWidth]:=Max(1,Result.Values[stRainbowRadius]*0.055);
        Result.Values[stRainbowTransparency]:=0;
      end;
    wpAurora:
      begin
        Result.Values[stHour]:=0;
        Result.Values[stOvercast]:=0;
        Result.Values[stSunTransparency]:=100;
        Result.Values[stAurora]:=100;
        Result.Values[stStars]:=55;
      end;
    wpMidsummer:
      begin
        Result.Values[stHour]:=13;
        Result.Values[stOvercast]:=30;
        Result.Values[stWindSpeed]:=8;
        Result.Values[stSunX]:=SceneWidth*0.18;
        Result.Values[stSunY]:=-SceneHeight*0.35;
        Result.Values[stSunSize]:=Min(SceneWidth,SceneHeight)*0.16;
        Result.Values[stSunStrength]:=175;
        Result.Values[stHeatHaze]:=60;
        Result.Values[stMirage]:=18;
      end;
  end;
  if Preset in [wpDawn,wpSunset] then
  begin
    // 反映時に下端の少し上へ配置する。保存後は通常のX/Yトラックとして自由に編集できる。
    Result.Values[stSunX]:=-SceneWidth*0.24;
    Result.Values[stSunY]:=SceneHeight*0.48-Result.Values[stSunSize]/2;
  end;
end;

end.
