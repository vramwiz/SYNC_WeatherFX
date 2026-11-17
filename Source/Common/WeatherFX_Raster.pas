unit WeatherFX_Raster;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// CPU の RGBA 合成と有限領域の図形描画。画素配列は描画器が所有し、フレーム間で再利用する。

interface

uses AviUtl2FilterTypes;

type
  TWeatherPixels = array of TPIXEL_RGBA;
  TWeatherRGB = record R,G,B: Double end;
  TWeatherRaster = class
  private
    FWidth, FHeight: Integer;
    FPixels: TWeatherPixels;
    FOpacity: Double;
    FOriginX,FOriginY: Double;
  public
    // 入力を複製して描画を始める。入力がない場合は透明で初期化する。
    // 入力配列とホスト所有ポインターは保持しない。
    procedure BeginFrame(const Input: TWeatherPixels; Width, Height: Integer; Opacity: Double);
    // 同一フレームへ別の演出を合成する際の中心と合成量。画像を消去しない。
    procedure SetLayer(Opacity: Double; OffsetX: Double = 0; OffsetY: Double = 0);
    // 色は0..1の直線的な演出値。RGBAは非乗算形式で保存し、source-overで合成する。
    procedure Blend(X,Y: Integer; const Color: TWeatherRGB; Alpha: Double);
    procedure FillRow(Y: Integer; const Color: TWeatherRGB);
    // 全面へ同じ色を重ねる。色と透明度の共通計算を画素ごとに繰り返さない。
    procedure Wash(const Color: TWeatherRGB; Alpha: Double);
    procedure Disc(CX,CY,Radius,Softness: Double; const Color: TWeatherRGB; Alpha: Double);
    // 統合型の粒子用。円の行範囲を絞り、共通値を事前計算する。従来のDiscは互換描画へ残す。
    procedure ParticleDisc(CX,CY,Radius,Softness: Double; const Color: TWeatherRGB; Alpha: Double);
    procedure Stroke(X1,Y1,X2,Y2,Radius,Softness: Double; const Color: TWeatherRGB; Alpha: Double);
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Pixels: TWeatherPixels read FPixels;
    property OriginX: Double read FOriginX;
    property OriginY: Double read FOriginY;
  end;

function RGB(Value: Cardinal; Brightness: Double = 1): TWeatherRGB;
function RGBMix(const A,B: TWeatherRGB; T: Double): TWeatherRGB;
function RGBScale(const A: TWeatherRGB; Scale: Double): TWeatherRGB;

implementation

uses System.Math, WeatherFX_Math;

function RGB(Value: Cardinal; Brightness: Double): TWeatherRGB;
begin
  Result.R := ((Value shr 16) and 255)/255*Brightness;
  Result.G := ((Value shr 8) and 255)/255*Brightness;
  Result.B := (Value and 255)/255*Brightness;
end;
function RGBMix(const A,B: TWeatherRGB; T: Double): TWeatherRGB;
begin Result.R:=Mix(A.R,B.R,T); Result.G:=Mix(A.G,B.G,T); Result.B:=Mix(A.B,B.B,T) end;
function RGBScale(const A: TWeatherRGB; Scale: Double): TWeatherRGB;
begin Result.R:=A.R*Scale; Result.G:=A.G*Scale; Result.B:=A.B*Scale end;

procedure TWeatherRaster.BeginFrame(const Input: TWeatherPixels; Width,Height: Integer; Opacity: Double);
begin
  FWidth := Width; FHeight := Height; FOpacity := Sat(Opacity);
  FOriginX:=Width/2; FOriginY:=Height/2;
  SetLength(FPixels, Width*Height);
  if Length(FPixels) = 0 then Exit;
  if Length(Input) = Length(FPixels) then
    Move(Input[0],FPixels[0],Length(FPixels)*SizeOf(TPIXEL_RGBA))
  else FillChar(FPixels[0],Length(FPixels)*SizeOf(TPIXEL_RGBA),0);
end;

procedure TWeatherRaster.SetLayer(Opacity,OffsetX,OffsetY: Double);
begin
  FOpacity:=Sat(Opacity); FOriginX:=FWidth/2+OffsetX; FOriginY:=FHeight/2+OffsetY;
end;

procedure TWeatherRaster.Blend(X,Y: Integer; const Color: TWeatherRGB; Alpha: Double);
var P: PPIXEL_RGBA; A,DA,OA,K: Double;
begin
  if (X<0) or (Y<0) or (X>=FWidth) or (Y>=FHeight) then Exit;
  A := Sat(Alpha*FOpacity);
  if A < 1/1024 then Exit;
  P := @FPixels[Y*FWidth+X];
  if (P^.A=0) or (A>=1) then
  begin
    P^.R:=Round(Sat(Color.R)*255); P^.G:=Round(Sat(Color.G)*255);
    P^.B:=Round(Sat(Color.B)*255); P^.A:=Round(A*255); Exit;
  end;
  if P^.A=255 then
  begin
    P^.R:=Round(Sat(Color.R)*255*A+P^.R*(1-A));
    P^.G:=Round(Sat(Color.G)*255*A+P^.G*(1-A));
    P^.B:=Round(Sat(Color.B)*255*A+P^.B*(1-A)); Exit;
  end;
  DA := P^.A/255;
  K := DA*(1-A); OA := A+K;
  P^.R := Round(Sat((Sat(Color.R)*A + P^.R/255*K)/OA)*255);
  P^.G := Round(Sat((Sat(Color.G)*A + P^.G/255*K)/OA)*255);
  P^.B := Round(Sat((Sat(Color.B)*A + P^.B/255*K)/OA)*255);
  P^.A := Round(OA*255);
end;

procedure TWeatherRaster.FillRow(Y: Integer; const Color: TWeatherRGB);
var X: Integer; P: TPIXEL_RGBA;
begin
  if FOpacity<1 then
  begin for X:=0 to FWidth-1 do Blend(X,Y,Color,1); Exit end;
  P.R:=Round(Sat(Color.R)*255); P.G:=Round(Sat(Color.G)*255);
  P.B:=Round(Sat(Color.B)*255); P.A:=255;
  for X:=0 to FWidth-1 do FPixels[Y*FWidth+X]:=P;
end;

procedure TWeatherRaster.Wash(const Color: TWeatherRGB; Alpha: Double);
var I: Integer; A,K,R,G,B: Double; P: TPIXEL_RGBA;
begin
  A:=Sat(Alpha*FOpacity); if A<1/1024 then Exit;
  K:=1-A; R:=Sat(Color.R)*255; G:=Sat(Color.G)*255; B:=Sat(Color.B)*255;
  P.R:=Round(R); P.G:=Round(G); P.B:=Round(B); P.A:=Round(A*255);
  for I:=0 to High(FPixels) do
    if (FPixels[I].A=0) or (A>=1) then FPixels[I]:=P
    else if FPixels[I].A=255 then
    begin
      FPixels[I].R:=Round(R*A+FPixels[I].R*K);
      FPixels[I].G:=Round(G*A+FPixels[I].G*K);
      FPixels[I].B:=Round(B*A+FPixels[I].B*K);
    end else Blend(I mod FWidth,I div FWidth,Color,Alpha);
end;
procedure TWeatherRaster.Disc(CX,CY,Radius,Softness: Double; const Color: TWeatherRGB; Alpha: Double);
var X,Y,L,R,T,B: Integer; D,Extent: Double;
begin
  if Radius<=0 then Exit;
  Extent := Radius+Max(1,Softness);
  L:=Max(0,Floor(CX-Extent)); R:=Min(FWidth-1,Ceil(CX+Extent));
  T:=Max(0,Floor(CY-Extent)); B:=Min(FHeight-1,Ceil(CY+Extent));
  for Y:=T to B do for X:=L to R do
  begin
    D:=Hypot(X+0.5-CX,Y+0.5-CY);
    Blend(X,Y,Color,Alpha*(1-Smooth(Max(0,Radius-Softness),Extent,D)));
  end;
end;

procedure TWeatherRaster.ParticleDisc(CX,CY,Radius,Softness: Double; const Color: TWeatherRGB; Alpha: Double);
var X,Y,L,R,T,B: Integer; E,Inner,InvSpan,DY2,Reach,U,DX: Double;
begin
  if (Radius<=0) or (Alpha<=0) then Exit;
  E:=Radius+Max(1,Softness); Inner:=Max(0,Radius-Softness);
  InvSpan:=1/Max(1E-9,E-Inner);
  T:=Max(0,Floor(CY-E)); B:=Min(FHeight-1,Ceil(CY+E));
  for Y:=T to B do
  begin
    DY2:=Sqr(Y+0.5-CY); if DY2>=E*E then Continue;
    Reach:=Sqrt(E*E-DY2);
    L:=Max(0,Ceil(CX-0.5-Reach)); R:=Min(FWidth-1,Floor(CX-0.5+Reach));
    for X:=L to R do
    begin
      DX:=X+0.5-CX;
      U:=Sat((Sqrt(DX*DX+DY2)-Inner)*InvSpan);
      Blend(X,Y,Color,Alpha*(1-U*U*(3-2*U)));
    end;
  end;
end;
procedure TWeatherRaster.Stroke(X1,Y1,X2,Y2,Radius,Softness: Double;
  const Color: TWeatherRGB; Alpha: Double);
var X,Y,L,R,T,B,RowL,RowR: Integer; DX,DY,Len2,U,D,E,TA,TB,XA,XB: Double;
begin
  if Radius<=0 then Exit;
  E:=Radius+Max(1,Softness);
  L:=Max(0,Floor(Min(X1,X2)-E)); R:=Min(FWidth-1,Ceil(Max(X1,X2)+E));
  T:=Max(0,Floor(Min(Y1,Y2)-E)); B:=Min(FHeight-1,Ceil(Max(Y1,Y2)+E));
  DX:=X2-X1; DY:=Y2-Y1; Len2:=Max(1E-9,DX*DX+DY*DY);
  for Y:=T to B do
  begin
    RowL:=L; RowR:=R;
    // 行の上下Eの帯と交差する線分だけを候補にし、斜めの雨の大きな空白領域を省く。
    if Abs(DY)>1E-9 then
    begin
      TA:=Sat((Y+0.5-E-Y1)/DY); TB:=Sat((Y+0.5+E-Y1)/DY);
      XA:=X1+DX*TA; XB:=X1+DX*TB;
      RowL:=Max(L,Floor(Min(XA,XB)-E)); RowR:=Min(R,Ceil(Max(XA,XB)+E));
    end;
    for X:=RowL to RowR do
    begin
      U:=Sat(((X+0.5-X1)*DX+(Y+0.5-Y1)*DY)/Len2);
      D:=Hypot(X+0.5-X1-U*DX,Y+0.5-Y1-U*DY);
      Blend(X,Y,Color,Alpha*(1-Smooth(Max(0,Radius-Softness),E,D)));
    end;
  end;
end;

end.
