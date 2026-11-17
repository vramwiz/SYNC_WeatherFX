unit WeatherFX_Celestial;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 太陽・月・光線・空・虹を解析的に描く。画像素材と地平線マスクは使用しない。

interface

uses WeatherFX_Settings, WeatherFX_Raster;

// Canvasの現在画像へ合成する。時刻は秒、進行状態は設定の時間軸を使用する。
procedure RenderCelestial(Canvas: TWeatherRaster; const S: TWeatherSettings; Time: Double);
// 統合型の太陽は高輝度の中心と周辺光を描く。月の表面処理と個別演出の互換経路は維持する。
procedure RenderSunLight(Canvas: TWeatherRaster; const S: TWeatherSettings; Time: Double);
// 朝夕の低い太陽の光。現在のX/Yへ追従し、背景色を残して局所的に明るくする。
procedure RenderSolarAtmosphere(C: TWeatherRaster; SunX,SunY,Diameter,Strength: Double);
// 既存の青空と同じ高度補間を、指定した時刻パレットで描画する。
procedure RenderSkyPalette(C: TWeatherRaster; const Top,Horizon,Bottom: TWeatherRGB; Brightness: Double);
// 朝夕の演出用。下端を地平線とし、青紫から赤・橙・黄へ滑らかに変える。
// SunXは画像内のピクセル座標。物理的な散乱計算ではなく、通常の空との連続補間で描く。
procedure RenderTwilightSky(C: TWeatherRaster; const Top,Horizon,Bottom: TWeatherRGB;
  Strength,Overcast,SunX: Double; Dawn: Boolean);
// 統合型では帯幅をピクセル、円弧角度を度で直接指定する。個別演出の既定動作は維持する。
procedure RenderRainbowLayer(C: TWeatherRaster; const S: TWeatherSettings;
  BandWidth,ArcDegrees: Double; SolidBand: Boolean);

implementation

uses System.Math, WeatherFX_Math;

procedure RenderBody(C: TWeatherRaster; const S: TWeatherSettings; Time: Double; Emissive: Boolean);
var X,Y,L,R,T,B,Seed,I: Integer;
  Radius,Glow,Extent,NX,NY,D,Z,Light,Texture,A,Phase,LX,LZ,CA,SA,U,V,
  CrX,CrY,CrR,CrD,Progress: Double;
  Col,BodyColor,HaloColor: TWeatherRGB;
begin
  Radius:=S.Values[wtSize]/2;
  if Radius<=0 then Exit;
  if (S.Family=wfMoon) and (S.Values[wtShape]<=0) then Exit;
  Seed:=Round(S.Values[wtSeed]); Glow:=S.Values[wtGlow]/100;
  Extent:=Radius*(1+Glow*3)+S.Values[wtBlur]+2;
  if Emissive then Extent:=Radius*(1+Glow*6)+S.Values[wtBlur]+2;
  L:=Max(0,Floor(C.OriginX-Extent)); R:=Min(C.Width-1,Ceil(C.OriginX+Extent));
  T:=Max(0,Floor(C.OriginY-Extent)); B:=Min(C.Height-1,Ceil(C.OriginY+Extent));
  BodyColor:=RGB(S.ColorRGB,S.Values[wtBrightness]/100);
  HaloColor:=RGBMix(RGB($FFF8E9),BodyColor,0.35);
  Progress:=S.Values[wtProgress]/100;
  if S.Style in [wsSunrise,wsSunset] then
  begin
    if S.Style=wsSunset then Progress:=1-Progress;
    Col:=RGBMix(RGB($E85632),RGB(S.ColorRGB),Progress);
    BodyColor:=RGBScale(Col,S.Values[wtBrightness]/100*Mix(0.75,1.1,Progress));
  end;
  Phase:=S.Values[wtShape]/100;
  LZ:=2*Phase-1; LX:=Sqrt(Max(0,1-LZ*LZ));
  CA:=Cos(DegToRad(S.Values[wtAngle])); SA:=Sin(DegToRad(S.Values[wtAngle]));
  for Y:=T to B do for X:=L to R do
  begin
    NX:=(X+0.5-C.OriginX)/Radius; NY:=(Y+0.5-C.OriginY)/Radius;
    D:=Hypot(NX,NY);
    if (Glow>0) and (D>0.95) then
    begin
      A:=Glow*0.30*Exp(-Max(0,D-1)*4/Max(0.05,Glow));
      if Emissive then
        A:=Glow*(0.80*Exp(-Max(0,D-1)*3.6)+0.28*Exp(-Max(0,D-1)*0.60));
      if S.Family=wfMoon then A:=A*Phase;
      if Emissive then C.Blend(X,Y,HaloColor,A) else C.Blend(X,Y,BodyColor,A);
    end;
    if D>1+(S.Values[wtBlur]+1)/Radius then Continue;
    A:=1-Smooth(1-(S.Values[wtBlur]+0.6)/Radius,1+(S.Values[wtBlur]+0.6)/Radius,D);
    if A<=0 then Continue;
    Z:=Sqrt(Max(0,1-D*D));
    if S.Family=wfMoon then
    begin
      U:=NX*CA+NY*SA; V:=-NX*SA+NY*CA;
      Light:=U*LX+Z*LZ;
      A:=A*Smooth(-0.012,0.018,Light);
      Texture:=0.65+0.35*Fractal(U*4+8,V*4+8,Seed);
      Texture:=Texture*(0.80+0.20*Noise(U*14,V*14,Seed+8));
      for I:=0 to 11 do
      begin
        CrX:=Random01(I,20,Seed)*1.7-0.85; CrY:=Random01(I,21,Seed)*1.7-0.85;
        CrR:=0.025+Random01(I,22,Seed)*0.09;
        CrD:=Hypot(U-CrX,V-CrY)/CrR;
        if CrD<1.3 then Texture:=Texture-0.09*Exp(-Sqr(CrD*1.5))+
          0.06*Exp(-Sqr((CrD-0.9)*6));
      end;
      Texture:=Mix(1,Texture,S.Values[wtDensity]/100);
      Col:=RGBScale(BodyColor,Texture*(0.65+0.35*Sqrt(Max(0,Light))));
    end else if Emissive then
    begin
      Texture:=0.997+0.003*Fractal(NX*12,NY*12,Seed);
      Col:=RGBMix(RGBScale(BodyColor,1.12*Texture),RGBScale(BodyColor,0.83),Smooth(0.75,1.02,D)*0.6);
    end else
    begin
      Texture:=0.93+0.07*Fractal(NX*12+Time*S.Values[wtSpeed]*0.025,NY*12,Seed);
      Col:=RGBScale(BodyColor,Texture*(0.73+0.27*Sqrt(Z)));
    end;
    C.Blend(X,Y,Col,A);
  end;
end;

procedure RenderSkyPalette(C: TWeatherRaster; const Top,Horizon,Bottom: TWeatherRGB; Brightness: Double);
var Y: Integer; H: Double; Col: TWeatherRGB;
begin
  for Y:=0 to C.Height-1 do
  begin
    H:=(Y+0.5)/C.Height;
    Col:=RGBMix(Top,Horizon,Power(H,0.85));
    Col:=RGBMix(Col,Bottom,Smooth(0.78,1,H)*0.45);
    C.FillRow(Y,RGBScale(Col,Brightness));
  end;
end;

procedure RenderTwilightSky(C: TWeatherRaster; const Top,Horizon,Bottom: TWeatherRGB;
  Strength,Overcast,SunX: Double; Dawn: Boolean);
var Y: Integer; H,Amount: Double; Base,Target,Upper,Rose,Orange,Gold: TWeatherRGB;
begin
  if Strength<=0 then begin RenderSkyPalette(C,Top,Horizon,Bottom,1); Exit end;
  Amount:=Sat(Strength)*(1-0.80*Sqr(Sat(Overcast)));
  Upper:=RGB($243D70); Rose:=RGB($C66A86); Orange:=RGB($FA854A); Gold:=RGB($FFD57C);
  if Dawn then
  begin Upper:=RGB($393F78); Rose:=RGB($CF8099); Orange:=RGB($FFA16D); Gold:=RGB($FFE2A0) end;
  for Y:=0 to C.Height-1 do
  begin
    H:=(Y+0.5)/C.Height;
    Base:=RGBMix(Top,Horizon,Power(H,0.85));
    Base:=RGBMix(Base,Bottom,Smooth(0.78,1,H)*0.45);
    if H<0.50 then Target:=RGBMix(Upper,Rose,Smooth(0.05,0.50,H))
    else if H<0.84 then Target:=RGBMix(Rose,Orange,Smooth(0.50,0.84,H))
    else Target:=RGBMix(Orange,Gold,Smooth(0.84,1,H));
    C.FillRow(Y,RGBMix(Base,Target,Amount));
  end;
end;

procedure RenderSolarAtmosphere(C: TWeatherRaster; SunX,SunY,Diameter,Strength: Double);
type TLightColumn = record Outer,Middle,Inner: Double end;
var X,Y,L,R,T,B,I: Integer; Radius,DX,DY,NearHorizon,OuterY,MiddleY,InnerY,
  Outer,Middle,Inner,ER,EG,EB,A: Double;
  Columns: array of TLightColumn; Pixels: TWeatherPixels; Color: TWeatherRGB;
begin
  if (Strength<=0) or (Diameter<=0) then Exit;
  Radius:=Diameter/2;
  NearHorizon:=(1-Smooth(1.5,5,(C.Height-SunY)/Radius))*
    (1-Smooth(0,3,(SunY-C.Height)/Radius));
  Strength:=Sat(Strength)*NearHorizon; if Strength<=0 then Exit;
  L:=Max(0,Floor(SunX-Radius*6)); R:=Min(C.Width-1,Ceil(SunX+Radius*6));
  T:=Max(0,Floor(SunY-Radius*4.5)); B:=Min(C.Height-1,Ceil(SunY+Radius*4.5));
  if (L>R) or (T>B) then Exit;
  SetLength(Columns,R-L+1);
  for X:=L to R do
  begin
    DX:=Sqr((X+0.5-SunX)/Radius);
    Columns[X-L].Outer:=Exp(-DX/13);
    Columns[X-L].Middle:=Exp(-DX/3.5);
    Columns[X-L].Inner:=Exp(-DX/0.9);
  end;
  Pixels:=C.Pixels; C.SetLayer(1);
  for Y:=T to B do
  begin
    DY:=Sqr((Y+0.5-SunY)/Radius)*1.30;
    OuterY:=Exp(-DY/13)*Strength; MiddleY:=Exp(-DY/3.5)*Strength; InnerY:=Exp(-DY/0.9)*Strength;
    for X:=L to R do
    begin
      Outer:=Columns[X-L].Outer*OuterY; Middle:=Columns[X-L].Middle*MiddleY; Inner:=Columns[X-L].Inner*InnerY;
      ER:=Sat(Outer*0.40+Middle*0.70+Inner*0.80);
      EG:=Sat(Outer*0.17+Middle*0.65+Inner*0.80);
      EB:=Sat(Outer*0.025+Middle*0.28+Inner*0.72);
      if ER<1/1024 then Continue;
      I:=Y*C.Width+X;
      if Pixels[I].A=255 then
      begin
        // スクリーン合成で背景の色を残し、太陽へ近づくほど光へ溶け込ませる。
        Pixels[I].R:=Round(Pixels[I].R+(255-Pixels[I].R)*ER);
        Pixels[I].G:=Round(Pixels[I].G+(255-Pixels[I].G)*EG);
        Pixels[I].B:=Round(Pixels[I].B+(255-Pixels[I].B)*EB);
      end else
      begin
        A:=ER; Color.R:=1; Color.G:=EG/A; Color.B:=EB/A;
        C.Blend(X,Y,Color,A);
      end;
    end;
  end;
end;
procedure RenderSky(C: TWeatherRaster; const S: TWeatherSettings);
var P: Double; Top,Horizon,Bottom: TWeatherRGB;
begin
  P:=S.Values[wtProgress]/100;
  Top:=RGB($1762B5); Horizon:=RGB($B9DEEE); Bottom:=RGB(S.ColorRGB);
  case S.Style of
    wsDawnSky:
      begin Top:=RGBMix(RGB($172749),RGB($467FB0),P);
        Horizon:=RGBMix(RGB($BC6574),RGB($FFD7A1),P); Bottom:=RGB(S.ColorRGB) end;
    wsSunsetSky:
      begin Top:=RGBMix(RGB($496B99),RGB($161E44),P);
        Horizon:=RGBMix(RGB($FFC37E),RGB($C05B69),P); Bottom:=RGB(S.ColorRGB) end;
    wsTwilight: begin Top:=RGB($182447); Horizon:=RGB($B58A9D); Bottom:=RGB(S.ColorRGB) end;
    wsNightSky: begin Top:=RGB($030A21); Horizon:=RGB($23375A); Bottom:=RGB(S.ColorRGB) end;
  end;
  RenderSkyPalette(C,Top,Horizon,Bottom,S.Values[wtBrightness]/100);
end;

procedure RenderRays(C: TWeatherRaster; const S: TWeatherSettings; Time: Double);
var X,Y,Seed,GX,GY,GW,GH,Step,I: Integer;
  DX,DY,U,V,A,Len,CA,SA,Spread,Theta,Pattern,Fade,Drift,Count: Double;
  Col: TWeatherRGB; Grid: array of Double;
begin
  Len:=S.Values[wtSize]; if Len<=0 then Exit;
  Count:=S.Values[wtAmount]; if Count<=0 then Exit;
  CA:=Cos(DegToRad(S.Values[wtAngle])); SA:=Sin(DegToRad(S.Values[wtAngle]));
  Spread:=0.08+S.Values[wtSpread]/100*1.3;
  Drift:=Time*S.Values[wtSpeed]*0.12*S.Values[wtSway]/100;
  Seed:=Round(S.Values[wtSeed]);
  Col:=RGB(S.ColorRGB,S.Values[wtBrightness]/100);
  // 光線の連続場を格子で評価し、画素ごとのノイズ・三角関数を省く。
  Step:=EnsureRange(C.Width div 480,2,8);
  GW:=(C.Width+Step-1) div Step+1; GH:=(C.Height+Step-1) div Step+1;
  SetLength(Grid,GW*GH);
  for GY:=0 to GH-1 do for GX:=0 to GW-1 do
  begin
    DX:=GX*Step+0.5-C.OriginX; DY:=GY*Step+0.5-C.OriginY;
    U:=DX*CA+DY*SA; V:=-DX*SA+DY*CA;
    if S.Style=wsRays then
    begin
      U:=Hypot(DX,DY); Theta:=ArcTan2(DY,DX);
      Pattern:=Power(Sat(Noise(Cos(Theta)*Count*0.7+8,
        Sin(Theta)*Count*0.7+8+Drift,Seed)*1.8-0.4),Mix(6,1.5,S.Values[wtBlur]/100));
      Fade:=Smooth(0,Len*0.07,U)*(1-Smooth(Len*0.1,Len,U));
    end else
    begin
      if (U<0) or (U>Len) then Continue;
      Theta:=V/(30+U*Spread);
      Fade:=(1-Smooth(0.55,1,Abs(Theta)))*Smooth(0,20+S.Values[wtBlur],U)*
        (1-Smooth(Len*0.45,Len,U));
      Pattern:=Power(Sat(Noise(Theta*Count*3+8,Drift,Seed)*1.7-0.3),
        Mix(5,1.2,S.Values[wtBlur]/100));
      if S.Style=wsDappled then Pattern:=Pattern*
        Smooth(0.35,0.7,Fractal(V/35+8,U/60-Drift,Seed+10));
    end;
    A:=Fade*Mix(0.08,0.75,Pattern)*(0.65+S.Values[wtGlow]/200);
    Grid[GY*GW+GX]:=A;
  end;
  for Y:=0 to C.Height-1 do
  begin
    GY:=Y div Step; V:=(Y mod Step)/Step;
    for X:=0 to C.Width-1 do
    begin
      GX:=X div Step; U:=(X mod Step)/Step; I:=GY*GW+GX;
      A:=Mix(Mix(Grid[I],Grid[I+1],U),Mix(Grid[I+GW],Grid[I+GW+1],U),V);
      C.Blend(X,Y,Col,A);
    end;
  end;
end;

function Spectrum(T: Double): TWeatherRGB;
const Colors: array[0..6] of Cardinal = ($8B65D5,$6168DD,$529BD8,$69BD8F,$E2D97C,$EDAF71,$E77775);
var I: Integer; U: Double;
begin
  U:=Sat(T)*6; I:=Min(5,Floor(U)); Result:=RGBMix(RGB(Colors[I]),RGB(Colors[I+1]),U-I);
end;

procedure RenderRainbowLayer(C: TWeatherRaster; const S: TWeatherSettings;
  BandWidth,ArcDegrees: Double; SolidBand: Boolean);
var X,Y,Band,L,R,T,B: Integer; DX,DY,U,V,CA,SA,D,Radius,Thickness,Q,A,Theta,Arc,
  Inner2,Outer2,Extent,Glow,Halo,ArcFade: Double;
  Col,Tint: TWeatherRGB;
begin
  Radius:=S.Values[wtSize]; if Radius<=0 then Exit;
  Thickness:=Max(2,Radius*(0.025+S.Values[wtSpread]*0.0006));
  Arc:=Pi*S.Values[wtShape]/100;
  if BandWidth>=0 then Thickness:=Max(0.1,BandWidth);
  if ArcDegrees>=0 then Arc:=DegToRad(ArcDegrees);
  Glow:=S.Values[wtGlow]/100;
  CA:=Cos(DegToRad(S.Values[wtAngle])); SA:=Sin(DegToRad(S.Values[wtAngle]));
  Tint:=RGB(S.ColorRGB,S.Values[wtBrightness]/100);
  Halo:=Thickness*(0.65+Glow*3)+S.Values[wtBlur]+1;
  Extent:=Radius*(1+Ord(S.Values[wtAmount]>=1.5)*0.18)+Halo;
  Inner2:=Sqr(Max(0,Radius-Halo)); Outer2:=Sqr(Extent);
  L:=Max(0,Floor(C.OriginX-Extent)); R:=Min(C.Width-1,Ceil(C.OriginX+Extent));
  T:=Max(0,Floor(C.OriginY-Extent)); B:=Min(C.Height-1,Ceil(C.OriginY+Extent));
  for Y:=T to B do for X:=L to R do
  begin
    DX:=X+0.5-C.OriginX; DY:=Y+0.5-C.OriginY;
    D:=DX*DX+DY*DY;
    if (D<Inner2) or (D>Outer2) then Continue;
    U:=DX*CA+DY*SA; V:=-DX*SA+DY*CA;
    D:=Sqrt(D); Theta:=Abs(ArcTan2(U,-V));
    if Theta>Arc/2+0.05 then Continue;
    ArcFade:=1-Smooth(Max(0,Arc/2-0.08),Arc/2+0.05,Theta);
    if Arc>=2*Pi-1E-9 then ArcFade:=1;
    for Band:=0 to Ord(S.Values[wtAmount]>=1.5) do
    begin
      Q:=(D-Radius*(1+Band*0.18))/Thickness+0.5;
      A:=Smooth(-0.15-S.Values[wtBlur]/Thickness,0.15,Q)*
        (1-Smooth(0.85,1.15+S.Values[wtBlur]/Thickness,Q));
      A:=(A+Glow*0.14*Exp(-Sqr((Q-0.5)/(0.7+Glow))))*ArcFade;
      if A<0.002 then Continue;
      if Band=1 then Q:=1-Q;
      Col:=Spectrum(Q); Col.R:=Col.R*Tint.R; Col.G:=Col.G*Tint.G; Col.B:=Col.B*Tint.B;
      if SolidBand then C.Blend(X,Y,Col,A*Mix(1.0,0.38,Band))
      else C.Blend(X,Y,Col,A*Mix(0.70,0.26,Band));
    end;
  end;
end;

procedure RenderCelestial(Canvas: TWeatherRaster; const S: TWeatherSettings; Time: Double);
begin
  case S.Family of
    wfSun,wfMoon: RenderBody(Canvas,S,Time,False);
    wfSky: RenderSky(Canvas,S);
    wfRays: RenderRays(Canvas,S,Time);
    wfRainbow: RenderRainbowLayer(Canvas,S,-1,-1,False);
  end;
end;

procedure RenderSunLight(Canvas: TWeatherRaster; const S: TWeatherSettings; Time: Double);
begin RenderBody(Canvas,S,Time,True) end;

end.
