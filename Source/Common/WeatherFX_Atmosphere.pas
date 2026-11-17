unit WeatherFX_Atmosphere;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 統合型で追加する霧・オーロラ・風・雷・屈折。作業格子と画像の複製はインスタンスが所有する。

interface

uses WeatherFX_Raster;

type
  TAtmosphereNode = record R,G,B,A: Double end;
  TWeatherAtmosphere = class
  private
    FGrid: array of TAtmosphereNode;
    FSource: TWeatherPixels;
    procedure Field(C: TWeatherRaster; Kind: Integer; Amount,DX,DY,Time: Double;
      Seed: Integer; const Tint: TWeatherRGB);
  public
    // 以下は呼出中だけCanvasを借用する。無効量では格子・画素計算を省略する。
    procedure Fog(C: TWeatherRaster; Amount,WindX,WindY,Time: Double;
      Seed: Integer; const Tint: TWeatherRGB);
    procedure Aurora(C: TWeatherRaster; Amount,Time: Double; Seed: Integer);
    procedure Wind(C: TWeatherRaster; Amount,Speed,Direction,Time: Double; Seed: Integer);
    // Width=0で雷線なし、Flash=0で全面発光なし。同じイベント時刻を両方の描画へ使う。
    procedure Lightning(C: TWeatherRaster; Amount,Width,Flash,Time: Double; Seed: Integer);
    // Canvasの現在画像を複製して屈折させる。RGBAの補間はアルファ乗算で行い、色のにじみを防ぐ。
    procedure Refract(C: TWeatherRaster; Heat,Mirage,Time: Double; Seed: Integer);
  end;

implementation

uses System.Math, WeatherFX_Math, AviUtl2FilterTypes;

procedure TWeatherAtmosphere.Field(C: TWeatherRaster; Kind: Integer;
  Amount,DX,DY,Time: Double; Seed: Integer; const Tint: TWeatherRGB);
var X,Y,GX,GY,GW,GH,Step,I,StartX,EndX: Integer; U,V,N,A,Curve,Distance,Shade: Double;
  A00,A10,A01,A11: Double;
  Col: TWeatherRGB;
begin
  if Amount<=0 then Exit;
  C.SetLayer(Amount/100);
  Step:=EnsureRange(C.Width div 200,4,12);
  GW:=(C.Width+Step-1) div Step+1; GH:=(C.Height+Step-1) div Step+1;
  SetLength(FGrid,GW*GH);
  for GY:=0 to GH-1 do for GX:=0 to GW-1 do
  begin
    U:=GX*Step/Max(1,C.Width); V:=GY*Step/Max(1,C.Height);
    if Kind=0 then
    begin
      N:=Fractal((GX*Step-DX*Time)/Max(320,C.Width*0.72),
        (GY*Step-DY*Time)/Max(180,C.Height*0.48),Seed+317);
      A:=Sat(0.48+0.34*Smooth(0.26,0.72,N)+0.12*V);
      Col:=Tint;
    end else
    begin
      Curve:=0.28+0.07*Sin(U*6+Time*0.17)+0.035*Sin(U*15-Time*0.27);
      Distance:=V-Curve;
      Shade:=0.25+0.75*Sqr(Noise(U*75+Noise(U*5,Time*0.08,Seed),Time*0.14,Seed+91));
      A:=Exp(-Sqr(Distance/0.075))*Shade*Smooth(0,0.12,U)*(1-Smooth(0.88,1,U));
      Col:=RGBMix(RGB($49E9A2),RGB($A17BEC),Sat((Curve-V)/0.12+0.25));
    end;
    I:=GY*GW+GX; FGrid[I].R:=Col.R; FGrid[I].G:=Col.G; FGrid[I].B:=Col.B; FGrid[I].A:=A;
  end;
  if Kind=0 then
  begin
    for Y:=0 to C.Height-1 do
    begin
      GY:=Y div Step; V:=(Y mod Step)/Step;
      for GX:=0 to GW-2 do
      begin
        I:=GY*GW+GX;
        A00:=FGrid[I].A; A10:=FGrid[I+1].A; A01:=FGrid[I+GW].A; A11:=FGrid[I+GW+1].A;
        StartX:=GX*Step; EndX:=Min(C.Width-1,StartX+Step-1);
        for X:=StartX to EndX do
        begin
          U:=(X-StartX)/Step;
          A:=Mix(Mix(A00,A10,U),Mix(A01,A11,U),V);
          C.Blend(X,Y,Tint,A);
        end;
      end;
    end;
    Exit;
  end;
  for Y:=0 to C.Height-1 do
  begin
    GY:=Y div Step; V:=(Y mod Step)/Step;
    for X:=0 to C.Width-1 do
    begin
      GX:=X div Step; U:=(X mod Step)/Step; I:=GY*GW+GX;
      A:=Mix(Mix(FGrid[I].A,FGrid[I+1].A,U),Mix(FGrid[I+GW].A,FGrid[I+GW+1].A,U),V);
      if A<0.001 then Continue;
      if Kind<>0 then
      begin
        Col.R:=Mix(Mix(FGrid[I].R,FGrid[I+1].R,U),Mix(FGrid[I+GW].R,FGrid[I+GW+1].R,U),V);
        Col.G:=Mix(Mix(FGrid[I].G,FGrid[I+1].G,U),Mix(FGrid[I+GW].G,FGrid[I+GW+1].G,U),V);
        Col.B:=Mix(Mix(FGrid[I].B,FGrid[I+1].B,U),Mix(FGrid[I+GW].B,FGrid[I+GW+1].B,U),V);
      end;
      C.Blend(X,Y,Col,A);
    end;
  end;
end;

procedure TWeatherAtmosphere.Fog(C: TWeatherRaster; Amount,WindX,WindY,Time: Double;
  Seed: Integer; const Tint: TWeatherRGB);
begin Field(C,0,Amount,WindX,WindY,Time,Seed,Tint) end;

procedure TWeatherAtmosphere.Aurora(C: TWeatherRaster; Amount,Time: Double; Seed: Integer);
begin Field(C,1,Amount,0,0,Time,Seed,RGB($FFFFFF)) end;

procedure TWeatherAtmosphere.Wind(C: TWeatherRaster; Amount,Speed,Direction,Time: Double; Seed: Integer);
var I,J,Count: Integer; CA,SA,X,Y,PX,PY,QX,QY,Length_,T,Curve,Phase: Double;
  Col: TWeatherRGB;
begin
  if Amount<=0 then Exit;
  C.SetLayer(Amount/100*0.18);
  CA:=Cos(DegToRad(Direction)); SA:=Sin(DegToRad(Direction));
  Count:=Min(300,Round(Amount*0.45*C.Width*C.Height/(960.0*540.0)));
  Length_:=80+Speed*2; Col:=RGB($D2E4F1);
  for I:=0 to Count-1 do
  begin
    X:=Wrap(Random01(I,8,Seed)*C.Width+Time*Speed*5*CA,C.Width+Length_)-Length_/2;
    Y:=Wrap(Random01(I,9,Seed)*C.Height+Time*Speed*5*SA,C.Height+Length_)-Length_/2;
    Phase:=Random01(I,10,Seed)*2*Pi;
    PX:=X; PY:=Y;
    for J:=1 to 10 do
    begin
      T:=J/10; Curve:=Sin(T*Pi*2+Phase+Time*Speed*0.01)*(7+Speed*0.12)*Sin(Pi*T);
      QX:=X+CA*Length_*T-SA*Curve; QY:=Y+SA*Length_*T+CA*Curve;
      C.Stroke(PX,PY,QX,QY,0.5,1.6,Col,Sin(Pi*T)*0.65); PX:=QX; PY:=QY;
    end;
  end;
end;

procedure TWeatherAtmosphere.Lightning(C: TWeatherRaster; Amount,Width,Flash,Time: Double; Seed: Integer);
var Cycle: Int64; I,J,Slot,X,Y: Integer;
  Period,Age,A,PX,PY,QX,QY,BX,BY,Angle_,Length_,Radius: Double; Col: TWeatherRGB;
begin
  if (Amount<=0) or ((Width<=0) and (Flash<=0)) then Exit;
  Radius:=Width/2;
  Period:=Mix(8,1.5,Amount/100); Col:=RGB($E4E9FF);
  for Slot:=0 to 1 do
  begin
    Cycle:=Floor((Time+Random01(Slot,41,Seed)*Period)/Period);
    Age:=Wrap(Time+Random01(Slot,41,Seed)*Period,Period);
    if Age>0.34 then Continue;
    A:=Exp(-Age*22)+0.65*Exp(-Sqr((Age-0.19)/0.035));
    C.SetLayer(Amount/100);
    if Flash>0 then C.Wash(Col,Sat(A)*Flash/100);
    if Width<=0 then Continue;
    PX:=(0.15+Random01(Cycle+Slot*71,42,Seed)*0.7)*C.Width; PY:=-5;
    for I:=1 to 15 do
    begin
      QX:=PX+(Random01(Cycle+I*83+Slot*71,43,Seed)-0.5)*C.Width*0.14;
      QY:=I*C.Height*0.065;
      C.Stroke(PX,PY,QX,QY,Radius*1.9,Radius*2.8+2,Col,A*0.28);
      C.Stroke(PX,PY,QX,QY,Radius,Max(0.6,Radius*0.25),RGB($FFFFFF),A);
      if (I>3) and (I mod 3=0) then
      begin
        BX:=PX; BY:=PY; Angle_:=(Random01(Cycle+I,44,Seed)-0.5)*1.8;
        Length_:=C.Height*(0.02+Random01(Cycle+I,45,Seed)*0.035);
        for J:=1 to 4 do
        begin
          X:=Round(BX+Sin(Angle_)*Length_+(Random01(I*4+J,Cycle,Seed)-0.5)*12);
          Y:=Round(BY+Cos(Angle_)*Length_);
          C.Stroke(BX,BY,X,Y,Max(0.4,Radius*0.32),1,Col,A*(1-J/5)); BX:=X; BY:=Y;
        end;
      end;
      PX:=QX; PY:=QY;
    end;
  end;
end;

procedure TWeatherAtmosphere.Refract(C: TWeatherRaster; Heat,Mirage,Time: Double; Seed: Integer);
var Dest: TWeatherPixels; X,Y,GX,GY,GW,GH,Step,I,X0,Y0,X1,Y1,J: Integer;
  U,V,SX,SY,Density,ReflectY,A,R,G,B: Double;
  P: array[0..3] of TPIXEL_RGBA; W: array[0..3] of Double;
begin
  if (Heat<=0) and (Mirage<=0) then Exit;
  Dest:=C.Pixels; SetLength(FSource,Length(Dest));
  Move(Dest[0],FSource[0],Length(Dest)*SizeOf(TPIXEL_RGBA));
  Step:=8; GW:=(C.Width+Step-1) div Step+1; GH:=(C.Height+Step-1) div Step+1;
  SetLength(FGrid,GW*GH);
  for GY:=0 to GH-1 do for GX:=0 to GW-1 do
  begin
    X:=GX*Step; Y:=GY*Step; Density:=Smooth(0.22,0.92,Y/Max(1,C.Height));
    I:=GY*GW+GX;
    FGrid[I].R:=(Noise(X/55,Y/25+Time*1.4,Seed+813)-0.5)*Heat*0.55*Density;
    ReflectY:=C.Height*1.25-Y*0.55;
    FGrid[I].G:=(Noise(X/70+Time*0.5,Y/45,Seed+817)-0.5)*Heat*0.13*Density+
      (ReflectY-Y)*Mirage/100*Smooth(0.58,0.98,Y/Max(1,C.Height));
  end;
  for Y:=Floor(C.Height*0.22) to C.Height-1 do
  begin
    GY:=Y div Step; V:=(Y mod Step)/Step;
    for X:=0 to C.Width-1 do
    begin
      GX:=X div Step; U:=(X mod Step)/Step; I:=GY*GW+GX;
      SX:=EnsureRange(X+Mix(Mix(FGrid[I].R,FGrid[I+1].R,U),Mix(FGrid[I+GW].R,FGrid[I+GW+1].R,U),V),0.0,C.Width-1.0);
      SY:=EnsureRange(Y+Mix(Mix(FGrid[I].G,FGrid[I+1].G,U),Mix(FGrid[I+GW].G,FGrid[I+GW+1].G,U),V),0.0,C.Height-1.0);
      if (Abs(SX-X)<1E-6) and (Abs(SY-Y)<1E-6) then Continue;
      X0:=Floor(SX); Y0:=Floor(SY); X1:=Min(C.Width-1,X0+1); Y1:=Min(C.Height-1,Y0+1);
      U:=SX-X0; V:=SY-Y0;
      P[0]:=FSource[Y0*C.Width+X0]; P[1]:=FSource[Y0*C.Width+X1];
      P[2]:=FSource[Y1*C.Width+X0]; P[3]:=FSource[Y1*C.Width+X1];
      W[0]:=(1-U)*(1-V); W[1]:=U*(1-V); W[2]:=(1-U)*V; W[3]:=U*V;
      A:=0; R:=0; G:=0; B:=0;
      for J:=0 to 3 do
      begin Density:=W[J]*P[J].A; A:=A+Density; R:=R+P[J].R*Density;
        G:=G+P[J].G*Density; B:=B+P[J].B*Density end;
      I:=Y*C.Width+X;
      if A>0 then begin Dest[I].R:=Round(R/A); Dest[I].G:=Round(G/A); Dest[I].B:=Round(B/A) end
      else begin Dest[I].R:=0; Dest[I].G:=0; Dest[I].B:=0 end;
      Dest[I].A:=Round(A);
      V:=(Y mod Step)/Step;
    end;
  end;
end;

end.
