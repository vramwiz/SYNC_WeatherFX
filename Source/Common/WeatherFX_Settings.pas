unit WeatherFX_Settings;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// スタイルは描画系統と標準項目の初期値を定義する。描画中は設定を書き換えない。

interface

type
  TWeatherFamily = (wfSun, wfRays, wfMoon, wfSky, wfStars, wfMeteor,
    wfCloud, wfRain, wfSnow, wfRainbow);
  TWeatherStyle = (wsSun, wsSunrise, wsSunset,
    wsSunlight, wsStrongSunlight, wsRays, wsCrepuscular, wsDappled,
    wsFullMoon, wsHalfMoon, wsCrescent, wsThinCrescent,
    wsWeakMoonlight, wsMoonlight, wsStrongMoonlight, wsMistyMoonlight,
    wsBlueSky, wsDawnSky, wsSunsetSky, wsTwilight, wsNightSky,
    wsStars, wsTwinklingStars, wsBrightStars, wsMeteor,
    wsWhiteCloud, wsBlackCloud, wsThinCloud, wsCirrocumulus, wsCumulonimbus, wsRainCloud,
    wsDrizzle, wsRain, wsHeavyRain, wsDownpour,
    wsLightSnow, wsSnow, wsHeavySnow, wsBlizzard,
    wsRainbow, wsSemicircle, wsShallowRainbow, wsDoubleRainbow, wsFaintRainbow);
  TWeatherTrack = (wtSize, wtAmount, wtSpeed, wtAngle, wtStrength, wtBrightness,
    wtBlur, wtGlow, wtDensity, wtSpread, wtShape, wtSway, wtRandomness,
    wtProgress, wtSeed);
  TWeatherTrackDefinition = record
    Name: PWideChar;
    MinValue, MaxValue, Step: Double;
  end;
  TWeatherSettings = record
    Style: TWeatherStyle;
    Family: TWeatherFamily;
    ColorRGB: Cardinal;
    Values: array[TWeatherTrack] of Double;
  end;

const
  WEATHER_STYLE_COUNT = Ord(High(TWeatherStyle)) + 1;
  WEATHER_MAX_PIXELS = 16777216;
  WEATHER_STYLE_NAMES: array[TWeatherStyle] of PWideChar = (
    '真昼の太陽', '朝日', '夕日',
    '通常の日差し', '強い日差し', '光芒', '薄明光線', '木漏れ日',
    '満月', '半月', '三日月', '細い三日月',
    '弱い月明かり', '通常の月明かり', '強い月明かり', '霧越しの月明かり',
    '青空', '朝焼け', '夕焼け', '薄暮', '夜空',
    '星空', 'きらめく星空', '明るい星空', '流れ星',
    '白い雲', '黒い雲', '薄雲', 'うろこ雲', '積乱雲', '雨雲',
    '小雨', '通常の雨', '大雨', '豪雨',
    '小雪', '通常の雪', '大雪', '吹雪',
    '通常の虹', '半円の虹', '浅い虹', '二重虹', '薄い虹');
  WEATHER_TRACKS: array[TWeatherTrack] of TWeatherTrackDefinition = (
    (Name:'サイズ'; MinValue:0; MaxValue:20000; Step:0.1),
    (Name:'量'; MinValue:0; MaxValue:1000; Step:0.01),
    (Name:'速度'; MinValue:0; MaxValue:2000; Step:0.01),
    (Name:'角度'; MinValue:-360; MaxValue:360; Step:0.1),
    (Name:'強さ'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'明るさ'; MinValue:0; MaxValue:300; Step:0.1),
    (Name:'ぼかし'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'発光'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'密度'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'広がり'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'形状'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'揺らぎ'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'ランダム性'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'時間軸'; MinValue:0; MaxValue:100; Step:0.1),
    (Name:'シード'; MinValue:0; MaxValue:1000000; Step:1));

// 独立した初期値を返す。位置・拡大率・透明度はホストの標準描画で制御する。
function WeatherPreset(Style: TWeatherStyle): TWeatherSettings;
// 外部値の非数・無限大を除き、標準項目の範囲に収める。
function WeatherClampTrack(Track: TWeatherTrack; Value: Double): Double;

implementation

uses System.Math;

function WeatherClampTrack(Track: TWeatherTrack; Value: Double): Double;
begin
  if IsNan(Value) or IsInfinite(Value) then Value := 0;
  Result := EnsureRange(Value, WEATHER_TRACKS[Track].MinValue, WEATHER_TRACKS[Track].MaxValue);
end;

function WeatherPreset(Style: TWeatherStyle): TWeatherSettings;
begin
  Result := Default(TWeatherSettings);
  Result.Style := Style;
  Result.ColorRGB := $FFF1CD;
  Result.Values[wtSize] := 160;
  Result.Values[wtAmount] := 1;
  Result.Values[wtSpeed] := 1;
  Result.Values[wtAngle] := 90;
  Result.Values[wtStrength] := 100;
  Result.Values[wtBrightness] := 100;
  Result.Values[wtBlur] := 1;
  Result.Values[wtGlow] := 45;
  Result.Values[wtDensity] := 55;
  Result.Values[wtSpread] := 50;
  Result.Values[wtShape] := 100;
  Result.Values[wtSway] := 25;
  Result.Values[wtRandomness] := 75;
  Result.Values[wtProgress] := 50;
  Result.Values[wtSeed] := 1;
  case Style of
    wsSun..wsSunset:
      begin
        Result.Family := wfSun;
        Result.Values[wtGlow] := 65;
        if Style <> wsSun then Result.ColorRGB := $FFAD55;
      end;
    wsSunlight..wsDappled, wsWeakMoonlight..wsMistyMoonlight:
      begin
        Result.Family := wfRays;
        Result.Values[wtSize] := 700;
        Result.Values[wtAmount] := 9;
        Result.Values[wtBlur] := 12;
        Result.Values[wtShape] := 50;
        Result.Values[wtStrength] := 35;
        Result.Values[wtSpeed] := 0.3;
        if Style in [wsWeakMoonlight..wsMistyMoonlight] then
        begin
          Result.ColorRGB := $B8D4FF;
          Result.Values[wtStrength] := 18;
          Result.Values[wtBlur] := 25;
        end;
        case Style of
          wsStrongSunlight: Result.Values[wtStrength] := 65;
          wsRays: begin Result.Values[wtAmount] := 24; Result.Values[wtSpread] := 100 end;
          wsCrepuscular: begin Result.Values[wtAmount] := 5; Result.Values[wtSpread] := 35 end;
          wsDappled: begin Result.Values[wtShape] := 85; Result.Values[wtSpread] := 85 end;
          wsWeakMoonlight: Result.Values[wtStrength] := 8;
          wsStrongMoonlight: Result.Values[wtStrength] := 35;
          wsMistyMoonlight: begin Result.Values[wtBlur] := 50; Result.Values[wtSpread] := 85 end;
        end;
      end;
    wsFullMoon..wsThinCrescent:
      begin
        Result.Family := wfMoon;
        Result.ColorRGB := $E3E3D2;
        Result.Values[wtGlow] := 15;
        Result.Values[wtAngle] := 0;
        Result.Values[wtDensity] := 65;
        case Style of
          wsHalfMoon: Result.Values[wtShape] := 50;
          wsCrescent: Result.Values[wtShape] := 18;
          wsThinCrescent: Result.Values[wtShape] := 7;
        end;
      end;
    wsBlueSky..wsNightSky:
      begin
        Result.Family := wfSky;
        Result.ColorRGB := $4391DA;
        Result.Values[wtSize] := 1000;
        case Style of
          wsDawnSky: Result.ColorRGB := $EBA979;
          wsSunsetSky: Result.ColorRGB := $D9654E;
          wsTwilight: Result.ColorRGB := $75658F;
          wsNightSky: Result.ColorRGB := $112548;
        end;
      end;
    wsStars..wsMeteor:
      begin
        Result.Family := wfStars;
        Result.ColorRGB := $E3EDFF;
        Result.Values[wtSize] := 2.4;
        Result.Values[wtAmount] := 160;
        Result.Values[wtGlow] := 35;
        Result.Values[wtSway] := 12;
        if Style = wsTwinklingStars then Result.Values[wtSway] := 80;
        if Style = wsBrightStars then
        begin Result.Values[wtSize] := 3.5; Result.Values[wtGlow] := 65 end;
        if Style = wsMeteor then
        begin
          Result.Family := wfMeteor;
          Result.Values[wtSize] := 3;
          Result.Values[wtAmount] := 0.65;
          Result.Values[wtSpeed] := 650;
          Result.Values[wtAngle] := 35;
          Result.Values[wtSpread] := 65;
        end;
      end;
    wsWhiteCloud..wsRainCloud:
      begin
        Result.Family := wfCloud;
        Result.ColorRGB := $EDF3FA;
        Result.Values[wtSize] := 800;
        Result.Values[wtSpeed] := 12;
        Result.Values[wtAngle] := 0;
        Result.Values[wtGlow] := 0;
        Result.Values[wtBlur] := 4;
        Result.Values[wtShape] := 55;
        case Style of
          wsBlackCloud: begin Result.ColorRGB := $3B4352; Result.Values[wtDensity] := 75 end;
          wsThinCloud: begin Result.Values[wtDensity] := 30; Result.Values[wtStrength] := 45 end;
          wsCirrocumulus: begin Result.Values[wtShape] := 90; Result.Values[wtDensity] := 45 end;
          wsCumulonimbus: begin Result.Values[wtShape] := 25; Result.Values[wtDensity] := 85 end;
          wsRainCloud: begin Result.ColorRGB := $5C667A; Result.Values[wtDensity] := 90 end;
        end;
      end;
    wsDrizzle..wsDownpour:
      begin
        Result.Family := wfRain;
        Result.ColorRGB := $BFD7ED;
        Result.Values[wtSize] := 1.4;
        Result.Values[wtAmount] := 180;
        Result.Values[wtSpeed] := 600;
        Result.Values[wtStrength] := 45;
        Result.Values[wtSpread] := 30;
        Result.Values[wtGlow] := 0;
        Result.Values[wtBlur] := 0.5;
        case Style of
          wsDrizzle: begin Result.Values[wtAmount] := 55; Result.Values[wtSize] := 0.8; Result.Values[wtSpeed] := 380 end;
          wsHeavyRain: begin Result.Values[wtAmount] := 420; Result.Values[wtSpread] := 55 end;
          wsDownpour: begin Result.Values[wtAmount] := 850; Result.Values[wtSpread] := 80; Result.Values[wtAngle] := 105 end;
        end;
      end;
    wsLightSnow..wsBlizzard:
      begin
        Result.Family := wfSnow;
        Result.ColorRGB := $F2F7FF;
        Result.Values[wtSize] := 5;
        Result.Values[wtAmount] := 110;
        Result.Values[wtSpeed] := 65;
        Result.Values[wtGlow] := 0;
        Result.Values[wtSway] := 55;
        Result.Values[wtBlur] := 1.2;
        case Style of
          wsLightSnow: Result.Values[wtAmount] := 40;
          wsHeavySnow: Result.Values[wtAmount] := 300;
          wsBlizzard: begin Result.Values[wtAmount] := 550; Result.Values[wtAngle] := 145; Result.Values[wtSpeed] := 300 end;
        end;
      end;
    wsRainbow..wsFaintRainbow:
      begin
        Result.Family := wfRainbow;
        Result.ColorRGB := $FFFFFF;
        Result.Values[wtSize] := 240;
        Result.Values[wtStrength] := 50;
        Result.Values[wtShape] := 80;
        Result.Values[wtBlur] := 3;
        Result.Values[wtGlow] := 8;
        Result.Values[wtAngle] := 0;
        Result.Values[wtSpread] := 55;
        case Style of
          wsSemicircle: Result.Values[wtShape] := 100;
          wsShallowRainbow: Result.Values[wtShape] := 45;
          wsDoubleRainbow: Result.Values[wtAmount] := 2;
          wsFaintRainbow: Result.Values[wtStrength] := 20;
        end;
      end;
  end;
end;

end.
