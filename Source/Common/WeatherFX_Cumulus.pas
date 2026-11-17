unit WeatherFX_Cumulus;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 積雲の密度・光の透過を立体格子で評価し、雲塊ごとの陰影付き画像へ保存する。
// 大小と重なりで遠近を付け、密度格子を色・時刻パレットから独立して再利用する。

interface

type
  TCloudSample = record Alpha,Shade: Double end;
  TCloudSamples = array of TCloudSample;
  TCloudSprite = record
    Nodes: TCloudSamples;
    Width,Height,Layer: Integer;
    MipCount: Integer;
    MipOffset,MipWidth,MipHeight: array[0..7] of Integer;
    CellX,CellY,LastUsed: Int64;
    Valid: Boolean;
  end;
  TWeatherCumulus = class
  private
    FNodes: TCloudSamples;
    FWidth,FHeight,FStep,FSeed: Integer;
    FDensity,FWindX,FWindY: Double;
    FValid: Boolean;
    FSprites: array[0..127] of TCloudSprite;
    FClock: Int64;
    FSpriteSeed: Integer;
    FSpritesValid: Boolean;
    function SpriteFor(CellX,CellY: Int64; Layer,Seed: Integer): Integer;
  public
    // WindX/Yはピクセル移動量。同じ条件では形状・陰影を再評価しない。
    procedure Build(Width,Height,Step: Integer; Density,WindX,WindY: Double; Seed: Integer);
    property Nodes: TCloudSamples read FNodes;
  end;

implementation

uses System.Math, WeatherFX_Math;

type
  TCloudLobe = record X,Y,Z,InvRX,InvRY,InvRZ: Double end;
  TCloudLobes = array[0..23] of TCloudLobe;
  TCloudRayLobe = record XY,Z,InvRZ: Double end;
  TCloudRayLobes = array[0..23] of TCloudRayLobe;
  TVolumeCell = record Density,Shadow: Single end;
  TVolumeCells = array of TVolumeCell;

procedure MakeLobes(Index: Int64; Seed: Integer; out Lobes: TCloudLobes);
var I: Integer; X,Arch,Lean: Double;
begin
  Arch:=0.18+Random01(Index,67,Seed)*0.50;
  Lean:=(Random01(Index,68,Seed)-0.5)*0.65;
  Lobes[0].X:=0; Lobes[0].Y:=0.06; Lobes[0].Z:=0;
  Lobes[0].InvRX:=1/(0.80+Random01(Index,69,Seed)*0.32);
  Lobes[0].InvRY:=1/(0.36+Random01(Index,70,Seed)*0.15); Lobes[0].InvRZ:=1/0.70;
  for I:=1 to High(Lobes) do
  begin
    X:=(Random01(Index*29+I,61,Seed)-0.5)*1.8;
    Lobes[I].Y:=-0.06-Arch*Sqrt(Max(0,1-X*X))+(Random01(Index*29+I,62,Seed)-0.5)*0.64;
    Lobes[I].X:=X+Lean*Lobes[I].Y;
    Lobes[I].Z:=(Random01(Index*29+I,63,Seed)-0.5)*0.86;
    Lobes[I].InvRX:=1/(0.24+Random01(Index*29+I,64,Seed)*0.38);
    Lobes[I].InvRY:=1/(0.22+Random01(Index*29+I,65,Seed)*0.44);
    Lobes[I].InvRZ:=1/(0.28+Random01(Index*29+I,66,Seed)*0.34);
  end;
  Lobes[1].X:=-0.60+Random01(Index,71,Seed)*1.10;
  Lobes[1].Y:=-0.20-Random01(Index,72,Seed)*0.55;
  Lobes[1].Z:=(Random01(Index,75,Seed)-0.5)*0.55;
  Lobes[1].InvRX:=1/(0.30+Random01(Index,73,Seed)*0.35);
  Lobes[1].InvRY:=1/(0.30+Random01(Index,74,Seed)*0.48); Lobes[1].InvRZ:=1/0.54;
  Lobes[2].X:=(Random01(Index,76,Seed)-0.5)*0.28;
  Lobes[2].Y:=-0.22; Lobes[2].Z:=0.20;
  Lobes[2].InvRX:=1/(0.70+Random01(Index,77,Seed)*0.22);
  Lobes[2].InvRY:=1/0.58; Lobes[2].InvRZ:=1/0.65;
end;

function VolumeNoise(X,Y,Z: Double; Seed: Integer): Double;
var IX,IY,IZ: Int64; U,V,W,A,B: Double; S0,S1: Integer;
begin
  IX:=Floor(X); IY:=Floor(Y); IZ:=Floor(Z);
  U:=X-IX; V:=Y-IY; W:=Z-IZ;
  U:=U*U*(3-2*U); V:=V*V*(3-2*V); W:=W*W*(3-2*W);
  S0:=Seed xor Integer(WeatherHash(IZ,91,Seed) and $7FFFFFFF);
  S1:=Seed xor Integer(WeatherHash(IZ+1,91,Seed) and $7FFFFFFF);
  A:=Mix(Mix(Random01(IX,IY,S0),Random01(IX+1,IY,S0),U),Mix(Random01(IX,IY+1,S0),Random01(IX+1,IY+1,S0),U),V);
  B:=Mix(Mix(Random01(IX,IY,S1),Random01(IX+1,IY,S1),U),Mix(Random01(IX,IY+1,S1),Random01(IX+1,IY+1,S1),U),V);
  Result:=Mix(A,B,W);
end;

function DensityAt(X,Y,Z: Double; const Lobes: TCloudRayLobes; Count,Seed: Integer): Double;
var I: Integer; Q,Field,Detail: Double;
begin
  Field:=0;
  for I:=0 to Count-1 do
  begin
    Q:=Lobes[I].XY+Sqr((Z-Lobes[I].Z)*Lobes[I].InvRZ);
    if Q<1 then Field:=Field+Sqr(1-Q);
  end;
  if Field<0.10 then Exit(0);
  Detail:=VolumeNoise(X*4+3,Y*4+7,Z*4,Seed)*0.52+
    VolumeNoise(X*8+11,Y*8-2,Z*8,Seed+71)*0.27+
    VolumeNoise(X*16,Y*16,Z*16,Seed+137)*0.14+
    VolumeNoise(X*32,Y*32,Z*32,Seed+209)*0.07;
  Result:=Sat((Field-0.28+(Detail-0.5)*0.85)*3.2);
end;

procedure BuildCloudSprite(Index: Int64; Seed,Layer: Integer; var Sprite: TCloudSprite);
var X,Y,Z,I,J,K,LobeIndex,ActiveCount,Stride,VolumeDepth,TextureSeed,
  Level,Total,SourceOffset,DestOffset,SW,SH,DW,DH,X0,X1,Y0,Y1: Integer;
  U,V,W,D,A,Trans,ShadeSum,Shadow,SX,SZ,FX,FZ,LightDX,LightDZ,LightStep,XY: Double;
  Lobes: TCloudLobes; Active: TCloudRayLobes; Grid: TVolumeCells;
  Samples: array[0..3] of TCloudSample;

  function Optical(AX,AZ,AY: Integer): Double;
  begin
    if (AX<0) or (AZ<0) or (AX>=Sprite.Width) or (AZ>=VolumeDepth) then Exit(0);
    Result:=Grid[AY*Stride+AZ*Sprite.Width+AX].Shadow;
  end;

begin
  case Layer of
    0: begin Sprite.Width:=192; Sprite.Height:=144; VolumeDepth:=40 end;
    1: begin Sprite.Width:=112; Sprite.Height:=88; VolumeDepth:=32 end;
    2: begin Sprite.Width:=64; Sprite.Height:=48; VolumeDepth:=24 end;
  else begin Sprite.Width:=40; Sprite.Height:=32; VolumeDepth:=20 end end;
  MakeLobes(Index,Seed,Lobes); Stride:=Sprite.Width*VolumeDepth;
  TextureSeed:=Integer(WeatherHash(Index,17,Seed) and $3FFFFFFF);
  LightStep:=2.6/(Sprite.Height-1);
  LightDX:=0.645*LightStep/(3.6/(Sprite.Width-1));
  LightDZ:=-0.844*LightStep/(2.2/VolumeDepth);
  SetLength(Grid,Stride*Sprite.Height);
  for Y:=0 to Sprite.Height-1 do
  begin
    V:=Y/(Sprite.Height-1)*2.6-1.8;
    for X:=0 to Sprite.Width-1 do
    begin
      U:=X/(Sprite.Width-1)*3.6-1.8;
      ActiveCount:=0;
      // 同じ視線上で共通のXY成分を一度だけ評価し、交差しない雲塊を除外する。
      for LobeIndex:=0 to High(Lobes) do
      begin
        XY:=Sqr((U-Lobes[LobeIndex].X)*Lobes[LobeIndex].InvRX)+
          Sqr((V-Lobes[LobeIndex].Y)*Lobes[LobeIndex].InvRY);
        if XY>=1 then Continue;
        Active[ActiveCount].XY:=XY; Active[ActiveCount].Z:=Lobes[LobeIndex].Z;
        Active[ActiveCount].InvRZ:=Lobes[LobeIndex].InvRZ; Inc(ActiveCount);
      end;
      for Z:=0 to VolumeDepth-1 do
      begin
        W:=-1.1+(Z+0.5)*2.2/VolumeDepth;
        I:=Y*Stride+Z*Sprite.Width+X;
        D:=0;
        if ActiveCount>0 then D:=DensityAt(U,V,W,Active,ActiveCount,TextureSeed);
        Grid[I].Density:=D;
        Shadow:=0;
        if Y>0 then
        begin
          SX:=X+LightDX; SZ:=Z+LightDZ;
          J:=Floor(SX); K:=Floor(SZ); FX:=SX-J; FZ:=SZ-K;
          Shadow:=Mix(Mix(Optical(J,K,Y-1),Optical(J+1,K,Y-1),FX),
            Mix(Optical(J,K+1,Y-1),Optical(J+1,K+1,Y-1),FX),FZ);
        end;
        Grid[I].Shadow:=Shadow+D*LightStep*9.2;
      end;
    end;
  end;
  SetLength(Sprite.Nodes,Sprite.Width*Sprite.Height);
  FillChar(Sprite.Nodes[0],Length(Sprite.Nodes)*SizeOf(TCloudSample),0);
  for Y:=0 to Sprite.Height-1 do for X:=0 to Sprite.Width-1 do
  begin
    Trans:=1; ShadeSum:=0;
    for Z:=0 to VolumeDepth-1 do
    begin
      I:=Y*Stride+Z*Sprite.Width+X; D:=Grid[I].Density;
      if D<0.002 then Continue;
      Shadow:=Grid[I].Shadow;
      A:=1-Exp(-D*2.2/VolumeDepth*15);
      ShadeSum:=ShadeSum+Trans*A*(0.48+0.65*Exp(-Shadow*0.95)+0.13*Exp(-Shadow*0.12));
      Trans:=Trans*(1-A); if Trans<0.003 then Break;
    end;
    Sprite.Nodes[Y*Sprite.Width+X].Alpha:=1-Trans;
    if Trans<0.999 then Sprite.Nodes[Y*Sprite.Width+X].Shade:=ShadeSum/(1-Trans);
  end;
  // 縮小時に雲の輪郭を点で拾わないよう、アルファ乗算で縮小した段階画像を作る。
  Sprite.MipCount:=0; Sprite.MipOffset[0]:=0;
  Sprite.MipWidth[0]:=Sprite.Width; Sprite.MipHeight[0]:=Sprite.Height;
  Total:=Sprite.Width*Sprite.Height;
  while (Sprite.MipCount<7) and
    ((Sprite.MipWidth[Sprite.MipCount]>1) or (Sprite.MipHeight[Sprite.MipCount]>1)) do
  begin
    Level:=Sprite.MipCount+1;
    Sprite.MipWidth[Level]:=Max(1,(Sprite.MipWidth[Level-1]+1) div 2);
    Sprite.MipHeight[Level]:=Max(1,(Sprite.MipHeight[Level-1]+1) div 2);
    Sprite.MipOffset[Level]:=Total;
    Inc(Total,Sprite.MipWidth[Level]*Sprite.MipHeight[Level]); Inc(Sprite.MipCount);
  end;
  SetLength(Sprite.Nodes,Total);
  for Level:=1 to Sprite.MipCount do
  begin
    SourceOffset:=Sprite.MipOffset[Level-1]; DestOffset:=Sprite.MipOffset[Level];
    SW:=Sprite.MipWidth[Level-1]; SH:=Sprite.MipHeight[Level-1];
    DW:=Sprite.MipWidth[Level]; DH:=Sprite.MipHeight[Level];
    for Y:=0 to DH-1 do for X:=0 to DW-1 do
    begin
      X0:=X*2; X1:=Min(SW-1,X0+1); Y0:=Y*2; Y1:=Min(SH-1,Y0+1);
      Samples[0]:=Sprite.Nodes[SourceOffset+Y0*SW+X0]; Samples[1]:=Sprite.Nodes[SourceOffset+Y0*SW+X1];
      Samples[2]:=Sprite.Nodes[SourceOffset+Y1*SW+X0]; Samples[3]:=Sprite.Nodes[SourceOffset+Y1*SW+X1];
      A:=0; ShadeSum:=0;
      for J:=0 to 3 do begin A:=A+Samples[J].Alpha; ShadeSum:=ShadeSum+Samples[J].Alpha*Samples[J].Shade end;
      I:=DestOffset+Y*DW+X; Sprite.Nodes[I].Alpha:=A*0.25; Sprite.Nodes[I].Shade:=1;
      if A>0 then Sprite.Nodes[I].Shade:=ShadeSum/A;
    end;
  end;
  Sprite.Valid:=True;
end;

function SampleSprite(U,V: Double; const Sprite: TCloudSprite; Level: Integer): TCloudSample;
var X,Y,X1,Y1,I,W,H,Offset: Integer; A,B: Double; P: array[0..3] of TCloudSample; Weights: array[0..3] of Double;
begin
  Result.Alpha:=0; Result.Shade:=1;
  W:=Sprite.MipWidth[Level]; H:=Sprite.MipHeight[Level]; Offset:=Sprite.MipOffset[Level];
  U:=(U+1.8)/3.6*(W-1); V:=(V+1.8)/2.6*(H-1);
  if (U<0) or (V<0) or (U>W-1) or (V>H-1) then Exit;
  X:=Floor(U); Y:=Floor(V); X1:=Min(W-1,X+1); Y1:=Min(H-1,Y+1);
  U:=U-X; V:=V-Y;
  P[0]:=Sprite.Nodes[Offset+Y*W+X]; P[1]:=Sprite.Nodes[Offset+Y*W+X1];
  P[2]:=Sprite.Nodes[Offset+Y1*W+X]; P[3]:=Sprite.Nodes[Offset+Y1*W+X1];
  Weights[0]:=(1-U)*(1-V); Weights[1]:=U*(1-V); Weights[2]:=(1-U)*V; Weights[3]:=U*V;
  A:=0; B:=0;
  for I:=0 to 3 do begin A:=A+P[I].Alpha*Weights[I]; B:=B+P[I].Alpha*P[I].Shade*Weights[I] end;
  Result.Alpha:=A; if A>0.001 then Result.Shade:=B/A;
end;

function TWeatherCumulus.SpriteFor(CellX,CellY: Int64; Layer,Seed: Integer): Integer;
var I: Integer; ShapeKey: Int64;
begin
  Inc(FClock);
  for I:=0 to High(FSprites) do
    if FSprites[I].Valid and (FSprites[I].CellX=CellX) and
      (FSprites[I].CellY=CellY) and (FSprites[I].Layer=Layer) then
    begin
      FSprites[I].LastUsed:=FClock; Exit(I);
    end;
  Result:=0;
  for I:=0 to High(FSprites) do
  begin
    if not FSprites[I].Valid then begin Result:=I; Break end;
    if FSprites[I].LastUsed<FSprites[Result].LastUsed then Result:=I;
  end;
  // 各空間セルの形を直接生成する。キャッシュの入替順は描画結果へ影響しない。
  FSprites[Result].Valid:=False;
  ShapeKey:=WeatherHash(CellX,CellY,Seed+Layer*7919) and $7FFFFFFF;
  BuildCloudSprite(ShapeKey,Seed,Layer,FSprites[Result]);
  FSprites[Result].CellX:=CellX; FSprites[Result].CellY:=CellY;
  FSprites[Result].Layer:=Layer; FSprites[Result].LastUsed:=FClock;
end;

procedure TWeatherCumulus.Build(Width,Height,Step: Integer; Density,WindX,WindY: Double; Seed: Integer);
var GW,GH,Row,Count,ShapeIndex,GX,GY,L,R,T,B,I,MipLevel: Integer;
  CellX,CellY,XMin,XMax,YMin,YMax,CloudKey: Int64;
  CX,CY,RX,RY,BaseRX,BaseRY,Presence,Visibility,Depth,Haze,Coverage,A,Combined,
  Spacing,PeriodY,OffsetX,OffsetY,MarginX,MarginY,MipBlend,Footprint,SampleU,SampleV: Double;
  Sprite: TCloudSprite; Sample,NextSample: TCloudSample;
begin
  if FValid and (Width=FWidth) and (Height=FHeight) and (Step=FStep) and
    (Seed=FSeed) and (Density=FDensity) and (WindX=FWindX) and (WindY=FWindY) then Exit;
  if (not FSpritesValid) or (Seed<>FSpriteSeed) then
  begin
    for I:=0 to High(FSprites) do FSprites[I].Valid:=False;
    FSpriteSeed:=Seed; FSpritesValid:=True;
  end;
  GW:=(Width+Step-1) div Step+1; GH:=(Height+Step-1) div Step+1;
  SetLength(FNodes,GW*GH); FillChar(FNodes[0],Length(FNodes)*SizeOf(TCloudSample),0);
  Presence:=Smooth(0,0.60,Density/100);
  for Row:=3 downto 0 do
  begin
    case Row of
      0: begin Count:=4; BaseRX:=0.18; BaseRY:=0.30 end;
      1: begin Count:=7; BaseRX:=0.085; BaseRY:=0.12 end;
      2: begin Count:=16; BaseRX:=0.036; BaseRY:=0.045 end;
    else begin Count:=24; BaseRX:=0.016; BaseRY:=0.018 end end;
    Spacing:=Width/Count;
    OffsetX:=WindX/(1+Row*2/3); OffsetY:=WindY/(1+Row*2/3);
    MarginX:=Width*BaseRX*1.4*1.8; MarginY:=Height*BaseRY*1.15*1.8;
    XMin:=Floor((-OffsetX-MarginX)/Spacing); XMax:=Ceil((Width-OffsetX+MarginX)/Spacing);
    PeriodY:=Height+MarginY*2;
    YMin:=Floor((-OffsetY-MarginY-Height)/PeriodY); YMax:=Ceil((Height-OffsetY+MarginY)/PeriodY);
    // 無限に続く空間から現在の画面にかかる雲だけを求める。
    // 風上側の隣セルも画面外から連続的に入るため、長時間でも雲が尽きない。
    for CellY:=YMin to YMax do for CellX:=XMin to XMax do
    begin
      CloudKey:=WeatherHash(CellX,CellY,Seed+Row*7919) and $7FFFFFFF;
      Visibility:=Smooth(Random01(CloudKey,51,Seed)*0.75,
        Random01(CloudKey,51,Seed)*0.75+0.25,Presence);
      if Visibility<=0 then Continue;
      Depth:=Sat(Row/3+(Random01(CloudKey,56,Seed)-0.5)*0.14);
      // 生成途中の雲は小さな不透明の雲から育て、雲全体を半透明にしない。
      A:=Visibility;
      RX:=Width*BaseRX*(0.65+Random01(CloudKey,52,Seed)*0.75)*A;
      RY:=Height*BaseRY*(0.85+Random01(CloudKey,53,Seed)*0.3)*A;
      Coverage:=Smooth(0,Step*1.5,Min(RX,RY));
      if Coverage<0.001 then Continue;
      CX:=(CellX+0.1+Random01(CloudKey,54,Seed)*0.8)*Spacing+OffsetX;
      case Row of
        0: CY:=Height*(-0.08+Random01(CloudKey,55,Seed)*0.42);
        1: CY:=Height*(0.42+Random01(CloudKey,55,Seed)*0.28);
        2: CY:=Height*(0.72+Random01(CloudKey,55,Seed)*0.16);
      else CY:=Height*(0.88+Random01(CloudKey,55,Seed)*0.09) end;
      CY:=CY+CellY*PeriodY+OffsetY;
      if (CX+RX*1.8<0) or (CX-RX*1.8>Width) or
        (CY+RY*0.8<0) or (CY-RY*1.8>Height) then Continue;
      ShapeIndex:=SpriteFor(CellX,CellY,Row,Seed); Sprite:=FSprites[ShapeIndex];
      Footprint:=Max((Sprite.Width-1)*Step/(3.6*RX),(Sprite.Height-1)*Step/(2.6*RY));
      MipBlend:=0;
      if Footprint>1 then MipBlend:=Min(Sprite.MipCount,Ln(Footprint)*1.4426950408889634);
      MipLevel:=Floor(MipBlend); MipBlend:=MipBlend-MipLevel;
      L:=Max(0,Floor((CX-RX*1.8)/Step)); R:=Min(GW-1,Ceil((CX+RX*1.8)/Step));
      T:=Max(0,Floor((CY-RY*1.8)/Step)); B:=Min(GH-1,Ceil((CY+RY*0.8)/Step));
      Haze:=Mix(1,0.82,Depth);
      for GY:=T to B do for GX:=L to R do
      begin
        SampleU:=(GX*Step-CX)/RX; SampleV:=(GY*Step-CY)/RY;
        Sample:=SampleSprite(SampleU,SampleV,Sprite,MipLevel);
        if MipBlend>0 then
        begin
          NextSample:=SampleSprite(SampleU,SampleV,Sprite,MipLevel+1);
          Combined:=Mix(Sample.Alpha,NextSample.Alpha,MipBlend);
          if Combined>0 then Sample.Shade:=Mix(Sample.Shade*Sample.Alpha,
            NextSample.Shade*NextSample.Alpha,MipBlend)/Combined;
          Sample.Alpha:=Combined;
        end;
        A:=Sample.Alpha*Haze*Coverage; if A<0.001 then Continue;
        I:=GY*GW+GX; Combined:=A+FNodes[I].Alpha*(1-A);
        FNodes[I].Shade:=(Sample.Shade*A+FNodes[I].Shade*FNodes[I].Alpha*(1-A))/Combined;
        FNodes[I].Alpha:=Combined;
      end;
    end;
  end;
  FWidth:=Width; FHeight:=Height; FStep:=Step; FSeed:=Seed;
  FDensity:=Density; FWindX:=WindX; FWindY:=WindY; FValid:=True;
end;

end.
