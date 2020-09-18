#!/usr/bin/env wolframscript
(* ::Package:: *)

<<"../source/ChebyshevSolver.wl"

(*<<"../../MBI-Resurgence/source/DeriveEinsteinEquationsFollowingCartwright.wl"

<<"../../MBI-Resurgence/source/NumericalPart.wl"

<<"../../MathematicaPackagesGit/DEQSystemStrucutureVisualization/source/DEQSystemStructureVisualization.wl"*)

DEQ = f[x] + f''[x] ;
chebPoints = 25;
x0 = -3.;
x1 = 3.;

ChebyshevSolver`ChebyNDSolve[{DEQ, a, b}, f, {x,x0,x1}]

(* Plot and Export for Viewing *)
plot = MatrixPlot[DerivMatrix];
Export["../TmpPlots/plot.png", plot]