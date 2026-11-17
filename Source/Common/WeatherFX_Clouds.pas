unit WeatherFX_Clouds;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 連続ノイズで雲の輪郭と濃淡を生成する。低解像度の場を補間し、画素ごとの多重ノイズ評価を避ける。

interface

uses WeatherFX_Settings, WeatherFX_Raster, WeatherFX_Cumulus;

type
  TWeatherCloudField = class
  private
    FGrid: array of TCloudSample;
    FThickGrid: TCloudSamples;
    FCumulus: TWeatherCumulus;
  public
    constructor Create;
    destructor Destroy; override;
    // 作業格子と積雲画像は本インスタンスが所有する。現在の設定を評価し、再生履歴へ依存しない。
    procedure Render(C: TWeatherRaster; const S: TWeatherSettings; Time: Double; FullSky: Boolean = False);
  end;

implementation

uses System.Math, WeatherFX_Math;

constructor TWeatherCloudField.Create;
begin inherited; FCumulus:=TWeatherCumulus.Create end;
destructor TWeatherCloudField.Destroy;
begin FCumulus.Free; inherited end;

procedure TWeatherCloudField.Render(C: TWeatherRaster; const S: TWeatherSettings; Time: Double; FullSky: Boolean);
var X,Y,GX,GY,GW,GH,Step,Seed,I,CoarseStep,CoarseWidth,CoarseHeight,CX,CY,StartX,EndX: Integer;
  Size,DX,DY,NX,NY,N,Detail,Envelope,Threshold,Soft,Drift,U,V,A,Shade,VolumeMix,CombinedAlpha: Double;
  P00,P10,P01,P11: TCloudSample; Col,LitColor: TWeatherRGB;
  Volume: TCloudSamples;

  function EvaluateNoise(PX,PY: Double): TCloudSample;
  var NU,NV,ND,NN: Double;
  begin
    NU:=(PX-DX)/Max(8,Size)*5; NV:=(PY-DY)/Max(8,Size)*5.5;
    ND:=Noise(NU*0.45+Drift,NV*0.45,Seed+61);
    NN:=Fractal(NU+ND*0.45,NV+Drift+ND*0.35,Seed);
    Result.Alpha:=Smooth(Threshold-Soft,Threshold+0.13,NN);
    Result.Alpha:=Mix(Result.Alpha,1,Smooth(75,100,S.Values[wtDensity]));
    Result.Shade:=EnsureRange(0.58+(NN-0.3)*0.7+
      (NN-Fractal(NU-0.12+ND*0.45,NV-0.18+Drift+ND*0.35,Seed))*1.8,0.35,1.1);
  end;

begin
  Size:=S.Values[wtSize]; if Size<=0 then Exit;
  Seed:=Round(S.Values[wtSeed]);
  Step:=EnsureRange(C.Width div 160,4,12);
  if FullSky then Step:=EnsureRange(C.Width div 480,2,6);
  GW:=(C.Width+Step-1) div Step+1; GH:=(C.Height+Step-1) div Step+1;
  SetLength(FGrid,GW*GH);
  DX:=Time*S.Values[wtSpeed]*Cos(DegToRad(S.Values[wtAngle]));
  DY:=Time*S.Values[wtSpeed]*Sin(DegToRad(S.Values[wtAngle]));
  Drift:=Time*S.Values[wtSpeed]*0.0009;
  VolumeMix:=0;
  if FullSky then VolumeMix:=1-Smooth(55,75,S.Values[wtDensity]);
  if VolumeMix>0 then
  begin
    FCumulus.Build(C.Width,C.Height,Step,S.Values[wtDensity],DX,DY,Seed);
    Volume:=FCumulus.Nodes;
  end;
  Threshold:=Mix(0.68,0.29,S.Values[wtDensity]/100);
  if FullSky then Threshold:=Mix(0.72,0.22,S.Values[wtDensity]/100);
  Soft:=0.04+S.Values[wtBlur]*0.003;
  // 厚い被覆は従来と同じ粗い格子で評価する。積雲の輪郭用格子へはアルファ乗算で補間する。
  CoarseWidth:=0; CoarseHeight:=0; CoarseStep:=1;
  if FullSky and (VolumeMix<1) then
  begin
    CoarseStep:=EnsureRange(C.Width div 160,4,12);
    CoarseWidth:=(C.Width+CoarseStep-1) div CoarseStep+1;
    CoarseHeight:=(C.Height+CoarseStep-1) div CoarseStep+1;
    SetLength(FThickGrid,CoarseWidth*CoarseHeight);
    for CY:=0 to CoarseHeight-1 do for CX:=0 to CoarseWidth-1 do
      FThickGrid[CY*CoarseWidth+CX]:=EvaluateNoise(CX*CoarseStep,CY*CoarseStep);
  end;
  for GY:=0 to GH-1 do for GX:=0 to GW-1 do
  begin
    I:=GY*GW+GX;
    if VolumeMix>=1 then begin FGrid[I]:=Volume[I]; Continue end;
    if FullSky then
    begin
      U:=GX*Step/CoarseStep; V:=GY*Step/CoarseStep;
      CX:=Min(CoarseWidth-2,Floor(U)); CY:=Min(CoarseHeight-2,Floor(V));
      U:=Sat(U-CX); V:=Sat(V-CY);
      P00:=FThickGrid[CY*CoarseWidth+CX]; P10:=FThickGrid[CY*CoarseWidth+CX+1];
      P01:=FThickGrid[(CY+1)*CoarseWidth+CX]; P11:=FThickGrid[(CY+1)*CoarseWidth+CX+1];
      A:=Mix(Mix(P00.Alpha,P10.Alpha,U),Mix(P01.Alpha,P11.Alpha,U),V);
      Shade:=0;
      if A>0.001 then Shade:=Mix(Mix(P00.Shade*P00.Alpha,P10.Shade*P10.Alpha,U),
        Mix(P01.Shade*P01.Alpha,P11.Shade*P11.Alpha,U),V)/A;
      FGrid[I].Alpha:=A; FGrid[I].Shade:=Shade;
    end else
    begin
    NX:=(GX*Step-C.Width/2)/Max(8,Size);
    NY:=(GY*Step-C.Height/2)/Max(8,Size);
    Envelope:=1-Smooth(0.60,1.1,Hypot(NX*1.5,NY*Mix(2.0,4.5,S.Values[wtShape]/100)));
    if FullSky then Envelope:=1;
    U:=(GX*Step-DX)/Max(8,Size)*5;
    V:=(GY*Step-DY)/Max(8,Size)*5.5;
    Detail:=Noise(U*0.45+Drift,V*0.45,Seed+61);
    N:=Fractal(U+Detail*0.45,V+Drift+Detail*0.35,Seed);
    if S.Style=wsCirrocumulus then
      N:=Mix(N,Fractal(U*3.5,V*2.0+Drift,Seed+97),0.70);
    I:=GY*GW+GX;
    FGrid[I].Alpha:=Smooth(Threshold-Soft,Threshold+0.13,N)*Envelope;
    if FullSky then FGrid[I].Alpha:=Mix(FGrid[I].Alpha,1,Smooth(75,100,S.Values[wtDensity]));
    if S.Style=wsThinCloud then FGrid[I].Alpha:=FGrid[I].Alpha*0.65;
    FGrid[I].Shade:=EnsureRange(0.58+(N-0.3)*0.7+
      (N-Fractal(U-0.12+Detail*0.45,V-0.18+Drift+Detail*0.35,Seed))*1.8,0.35,1.1);
    end;
    if VolumeMix>0 then
    begin
      CombinedAlpha:=Mix(FGrid[I].Alpha,Volume[I].Alpha,VolumeMix);
      if CombinedAlpha>0.001 then
        FGrid[I].Shade:=(FGrid[I].Shade*FGrid[I].Alpha*(1-VolumeMix)+
          Volume[I].Shade*Volume[I].Alpha*VolumeMix)/CombinedAlpha;
      FGrid[I].Alpha:=CombinedAlpha;
    end;
  end;
  Col:=RGB(S.ColorRGB,S.Values[wtBrightness]/100);
  if FullSky then
  begin
    // 4近傍の取得と陰影のアルファ乗算を格子セルごとに共有し、空のセルは描画しない。
    for Y:=0 to C.Height-1 do
    begin
      GY:=Y div Step; V:=(Y mod Step)/Step;
      for GX:=0 to GW-2 do
      begin
        I:=GY*GW+GX;
        P00:=FGrid[I]; P10:=FGrid[I+1]; P01:=FGrid[I+GW]; P11:=FGrid[I+GW+1];
        if Max(Max(P00.Alpha,P10.Alpha),Max(P01.Alpha,P11.Alpha))<0.002 then Continue;
        P00.Shade:=P00.Shade*P00.Alpha; P10.Shade:=P10.Shade*P10.Alpha;
        P01.Shade:=P01.Shade*P01.Alpha; P11.Shade:=P11.Shade*P11.Alpha;
        StartX:=GX*Step; EndX:=Min(C.Width-1,StartX+Step-1);
        for X:=StartX to EndX do
        begin
          U:=(X-StartX)/Step;
          A:=Mix(Mix(P00.Alpha,P10.Alpha,U),Mix(P01.Alpha,P11.Alpha,U),V);
          if A<0.002 then Continue;
          Shade:=Mix(Mix(P00.Shade,P10.Shade,U),Mix(P01.Shade,P11.Shade,U),V)/A;
          LitColor:=RGBScale(Col,Shade);
          if VolumeMix>0 then
          begin
            LitColor.R:=LitColor.R*(1-Sat((1-Shade)*2.5)*0.12*VolumeMix);
            LitColor.G:=LitColor.G*(1-Sat((1-Shade)*2.5)*0.03*VolumeMix);
          end;
          C.Blend(X,Y,LitColor,A);
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
      P00:=FGrid[I]; P10:=FGrid[I+1]; P01:=FGrid[I+GW]; P11:=FGrid[I+GW+1];
      A:=Mix(Mix(P00.Alpha,P10.Alpha,U),Mix(P01.Alpha,P11.Alpha,U),V);
      if A<0.002 then Continue;
      Shade:=Mix(Mix(P00.Shade,P10.Shade,U),Mix(P01.Shade,P11.Shade,U),V);
      if FullSky then
        Shade:=Mix(Mix(P00.Shade*P00.Alpha,P10.Shade*P10.Alpha,U),
          Mix(P01.Shade*P01.Alpha,P11.Shade*P11.Alpha,U),V)/A;
      LitColor:=RGBScale(Col,Shade);
      if VolumeMix>0 then
      begin
        LitColor.R:=LitColor.R*(1-Sat((1-Shade)*2.5)*0.12*VolumeMix);
        LitColor.G:=LitColor.G*(1-Sat((1-Shade)*2.5)*0.03*VolumeMix);
      end;
      C.Blend(X,Y,LitColor,A);
    end;
  end;
end;

end.
