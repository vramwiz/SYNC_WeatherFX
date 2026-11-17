unit WeatherFX_Particles;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 雨・雪・星・流れ星を時刻と固定ハッシュで直接配置する。衝突・積算・履歴は持たない。

interface

uses WeatherFX_Settings, WeatherFX_Raster;

procedure RenderWeatherParticles(C: TWeatherRaster; const S: TWeatherSettings; Time: Double; FastDiscs: Boolean = False);
// 統合型の流れ星。頻度は回/分、0で無効。各時間区間の発生時刻・軌道を固定ハッシュで決める。
procedure RenderMeteorShower(C: TWeatherRaster; const S: TWeatherSettings; Time,Frequency: Double);

implementation

uses System.Math, WeatherFX_Math;

procedure RenderField(C: TWeatherRaster; const S: TWeatherSettings; Time: Double; FastDiscs: Boolean);
var I,Count,Seed: Integer; X,Y,Size,Depth,CA,SA,Margin,SpanX,SpanY,Speed,
  Tail,A,Rnd,Phase,Twinkle: Double; Col,Tint: TWeatherRGB;
begin
  Count:=Min(12000,Round(S.Values[wtAmount]*C.Width*C.Height/(960.0*540.0)));
  if Count<=0 then Exit;
  Seed:=Round(S.Values[wtSeed]); Rnd:=S.Values[wtRandomness]/100;
  Size:=S.Values[wtSize]; if Size<=0 then Exit;
  Margin:=Min(200,Size*3+10);
  SpanX:=C.Width+Margin*2; SpanY:=C.Height+Margin*2;
  CA:=Cos(DegToRad(S.Values[wtAngle])); SA:=Sin(DegToRad(S.Values[wtAngle]));
  Col:=RGB(S.ColorRGB,S.Values[wtBrightness]/100);
  for I:=0 to Count-1 do
  begin
    Depth:=Mix(1,0.35+Random01(I,3,Seed)*0.9,Rnd);
    Speed:=S.Values[wtSpeed]*Depth;
    X:=Random01(I,0,Seed)*SpanX; Y:=Random01(I,1,Seed)*SpanY;
    Phase:=Random01(I,4,Seed)*2*Pi;
    if S.Family=wfStars then
    begin
      X:=Random01(I,0,Seed)*C.Width; Y:=Random01(I,1,Seed)*C.Height;
      Twinkle:=Mix(1,0.45+0.55*Sqr(Sin(Time*Speed*(0.5+Random01(I,6,Seed))+Phase)),S.Values[wtSway]/100);
      Tint:=RGBMix(Col,RGB($FFCE9B,S.Values[wtBrightness]/100),Random01(I,9,Seed)*Rnd*0.45);
      A:=(0.25+Depth*0.7)*Twinkle;
      if FastDiscs then C.ParticleDisc(X,Y,Size*Depth*0.35,0.8,Tint,A)
      else C.Disc(X,Y,Size*Depth*0.35,0.8,Tint,A);
      if S.Values[wtGlow]>0 then
      begin
        if FastDiscs then C.ParticleDisc(X,Y,Size*Depth*1.5,Size*Depth*1.3,Tint,A*S.Values[wtGlow]/400)
        else C.Disc(X,Y,Size*Depth*1.5,Size*Depth*1.3,Tint,A*S.Values[wtGlow]/400);
        if Depth>1.1 then
        begin
          C.Stroke(X-Size*1.8,Y,X+Size*1.8,Y,0.3,0.6,Tint,A*0.35);
          C.Stroke(X,Y-Size*1.8,X,Y+Size*1.8,0.3,0.6,Tint,A*0.35);
        end;
      end;
      Continue;
    end;
    X:=X+Time*Speed*CA; Y:=Y+Time*Speed*SA;
    if S.Family=wfSnow then X:=X+Sin(Time*S.Values[wtSpeed]*0.008+Phase)*S.Values[wtSway]*0.7*Depth;
    X:=Wrap(X,SpanX)-Margin; Y:=Wrap(Y,SpanY)-Margin;
    A:=EnsureRange(Depth,0.25,1.0);
    if S.Family=wfRain then
    begin
      Tail:=Min(300,Size*Depth*(6+S.Values[wtSpread]*0.65));
      C.Stroke(X,Y,X-CA*Tail,Y-SA*Tail,Size*Depth*0.35,S.Values[wtBlur],Col,A*0.7);
    end else if FastDiscs then
      C.ParticleDisc(X,Y,Size*Depth*0.5,S.Values[wtBlur]*(0.3+Depth*0.6),Col,A)
    else C.Disc(X,Y,Size*Depth*0.5,S.Values[wtBlur]*(0.3+Depth*0.6),Col,A);
  end;
end;

procedure RenderMeteor(C: TWeatherRaster; const S: TWeatherSettings; Time: Double);
var Slot,Seed,J: Integer; Cycle: Int64; Period,Age,Life,X,Y,CA,SA,Length_,A,Delay: Double;
  Col: TWeatherRGB;
begin
  if (S.Values[wtAmount]<=0) or (S.Values[wtSize]<=0) then Exit;
  Seed:=Round(S.Values[wtSeed]);
  Period:=Max(0.2,3/S.Values[wtAmount]); Life:=Min(1.2,Period*0.8);
  CA:=Cos(DegToRad(S.Values[wtAngle])); SA:=Sin(DegToRad(S.Values[wtAngle]));
  Col:=RGB(S.ColorRGB,S.Values[wtBrightness]/100);
  for Slot:=0 to 2 do
  begin
    Delay:=Random01(Slot,12,Seed)*Period;
    Cycle:=Floor((Time+Delay)/Period);
    Age:=Time+Delay-Cycle*Period;
    if Age>Life then Continue;
    X:=Random01(Integer(Cycle mod 1000000)+Slot*89,13,Seed)*C.Width*0.8;
    Y:=Random01(Integer(Cycle mod 1000000)+Slot*89,14,Seed)*C.Height*0.6;
    X:=X+CA*Age*S.Values[wtSpeed]; Y:=Y+SA*Age*S.Values[wtSpeed];
    A:=Smooth(0,Life*0.12,Age)*(1-Smooth(Life*0.65,Life,Age));
    Length_:=20+S.Values[wtSpread]*3;
    for J:=12 downto 1 do
      C.Stroke(X-CA*Length_*J/12,Y-SA*Length_*J/12,
        X-CA*Length_*(J-1)/12,Y-SA*Length_*(J-1)/12,
        S.Values[wtSize]*0.28,S.Values[wtBlur],Col,A*Sqr(1-J/13));
    C.Disc(X,Y,S.Values[wtSize]*0.5,1,Col,A);
    C.Disc(X,Y,S.Values[wtSize]*1.5,S.Values[wtSize]*1.5,Col,A*S.Values[wtGlow]/300);
  end;
end;

procedure RenderWeatherParticles(C: TWeatherRaster; const S: TWeatherSettings; Time: Double; FastDiscs: Boolean);
begin
  if S.Family=wfMeteor then RenderMeteor(C,S,Time) else RenderField(C,S,Time,FastDiscs);
end;

procedure RenderMeteorShower(C: TWeatherRaster; const S: TWeatherSettings; Time,Frequency: Double);
var First,Last,Event: Int64; Seed,J: Integer;
  Period,Age,Life,X,Y,Angle_,CA,SA,Tail,A,Speed: Double; Col: TWeatherRGB;
begin
  if (Frequency<=0) or (S.Values[wtSize]<=0) then Exit;
  Seed:=Round(S.Values[wtSeed]); Period:=60/Min(120,Frequency);
  First:=Floor((Time-1.2)/Period); Last:=Floor(Time/Period);
  Col:=RGB(S.ColorRGB,S.Values[wtBrightness]/100);
  for Event:=First to Last do
  begin
    Age:=Time-(Event+0.05+0.90*Random01(Event,312,Seed))*Period;
    Life:=0.60+Random01(Event,313,Seed)*0.60;
    if (Age<0) or (Age>Life) then Continue;
    Angle_:=DegToRad(22+Random01(Event,314,Seed)*30); CA:=Cos(Angle_); SA:=Sin(Angle_);
    Speed:=S.Values[wtSpeed]*(0.75+Random01(Event,315,Seed)*0.5);
    X:=(0.04+Random01(Event,316,Seed)*0.72)*C.Width+CA*Age*Speed;
    Y:=(0.03+Random01(Event,317,Seed)*0.38)*C.Height+SA*Age*Speed;
    A:=Smooth(0,Life*0.12,Age)*(1-Smooth(Life*0.65,Life,Age));
    Tail:=80+Random01(Event,318,Seed)*150;
    for J:=12 downto 1 do
      C.Stroke(X-CA*Tail*J/12,Y-SA*Tail*J/12,X-CA*Tail*(J-1)/12,Y-SA*Tail*(J-1)/12,
        S.Values[wtSize]*0.28,S.Values[wtBlur],Col,A*Sqr(1-J/13));
    C.Disc(X,Y,S.Values[wtSize]*0.5,1,Col,A);
    C.Disc(X,Y,S.Values[wtSize]*1.5,S.Values[wtSize]*1.5,Col,A*S.Values[wtGlow]/300);
  end;
end;

end.
