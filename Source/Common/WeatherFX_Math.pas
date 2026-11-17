unit WeatherFX_Math;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 時刻から直接評価する連続ノイズとハッシュ。乱数の進行状態を保持しない。

interface

function Sat(X: Double): Double; inline;
function Mix(A, B, T: Double): Double; inline;
function Smooth(A, B, X: Double): Double; inline;
function Wrap(X, Period: Double): Double; inline;
function WeatherHash(X, Y: Int64; Seed: Integer): Cardinal;
function Random01(Index, Salt: Int64; Seed: Integer): Double; inline;
function Noise(X, Y: Double; Seed: Integer): Double;
function Fractal(X, Y: Double; Seed: Integer): Double;

implementation

uses System.Math;

function Sat(X: Double): Double;
begin Result := EnsureRange(X, 0.0, 1.0) end;
function Mix(A, B, T: Double): Double;
begin Result := A + (B - A) * T end;
function Smooth(A, B, X: Double): Double;
var T: Double;
begin T := Sat((X - A) / Max(1E-9, B - A)); Result := T*T*(3 - 2*T) end;
function Wrap(X, Period: Double): Double;
begin Result := X - Floor(X / Period)*Period end;

{$IFOPT Q+}{$DEFINE RESTORE_OVERFLOW}{$ENDIF}
{$IFOPT R+}{$DEFINE RESTORE_RANGE}{$ENDIF}
{$Q-}{$R-}
function WeatherHash(X, Y: Int64; Seed: Integer): Cardinal;
begin
  Result := Cardinal(X)*$9E3779B1 xor Cardinal(Y)*$85EBCA77 xor Cardinal(Seed)*$C2B2AE3D;
  Result := (Result xor (Result shr 16))*$7FEB352D;
  Result := (Result xor (Result shr 15))*$846CA68B;
  Result := Result xor (Result shr 16);
end;
{$IFDEF RESTORE_OVERFLOW}{$Q+}{$UNDEF RESTORE_OVERFLOW}{$ENDIF}
{$IFDEF RESTORE_RANGE}{$R+}{$UNDEF RESTORE_RANGE}{$ENDIF}

function Random01(Index, Salt: Int64; Seed: Integer): Double;
begin Result := WeatherHash(Index, Salt, Seed) / 4294967296.0 end;

function Noise(X, Y: Double; Seed: Integer): Double;
var IX, IY: Int64; U,V: Double;
begin
  IX := Floor(X); IY := Floor(Y);
  U := X - IX; V := Y - IY;
  U := U*U*(3 - 2*U); V := V*V*(3 - 2*V);
  Result := Mix(Mix(Random01(IX,IY,Seed), Random01(IX+1,IY,Seed),U),
    Mix(Random01(IX,IY+1,Seed),Random01(IX+1,IY+1,Seed),U),V);
end;

function Fractal(X, Y: Double; Seed: Integer): Double;
begin
  Result := Noise(X,Y,Seed)*0.54 + Noise(X*2.03+5.7,Y*2.03-4.1,Seed+17)*0.27 +
    Noise(X*4.11-3.2,Y*4.11+9.3,Seed+31)*0.13 +
    Noise(X*8.23+7.4,Y*8.23+1.8,Seed+47)*0.06;
end;

end.
