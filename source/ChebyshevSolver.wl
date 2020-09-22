(*
Package: ChebyshevSolver
Author: Marco Knipfer
Email: mknipfer+chebyshev @ crimson . ua . edu
Institution: University of Alabama
Date: 09/2020
Description: This is a small package I wrote to solve a single ODE with a Chebyshev grid using
	the pseudospectral method. Only works for second order linear ODEs.
	The main functions are `ChebyshevSolver`ChebyNDSolve and `ChebyshevSolver`ChebyNDSolveRaw.
	The former one does exactly what the raw one does, but returns a function object by interpolating
	the solultion.
Usage: {sol, grid} = ChebyshevSolver`ChebyNDSolve[{DEQ, bc1, bc2}, f, {x,x0,x1}, "GridPoints"->chebPoints];
	- DEQ: the differential equation
	- bc1, bc2: boundary conditions. Right now they are only working at x0 or x1, but you can supply a funciton value or a derivative value there
	- {x,x0,x1}: Want to integrate the variable x from x0 to x1
	- Option: "GridPoints", number of grid points
Example:
	DEQ = x f[x] + 2 f'[x] + f''[x] == 0 ;
	x0 = 0.;
	x1 = 2 Pi;
	bc1 = f[x0] == 0.;
	bc2 = f'[x0] == 1.;
	chebPoints = 100;
	{sol, grid} = ChebyshevSolver`ChebyNDSolve[{DEQ, bc1, bc2}, f, {x,x0,x1}, "GridPoints"->chebPoints];
	plotCheb = ListPlot[Thread[{grid, sol}]];

	For the interpolated output:
	solInterpolated = ChebyshevSolver`ChebyNDSolve[{DEQ, bc1, bc2}, f, {x,x0,x1}, "GridPoints"->chebPoints];
	plotInterpolated = Plot[solInterpolated[x], {x,x0,x1}];
*)

BeginPackage["ChebyshevSolver`"];

Unprotect["ChebyshevSolver`*"];
ClearAll["ChebyshevSolver`*", "ChebyshevSolver`Private`*"];

(* Begin["`Private`"]; *)

StripArgument[expr_, arg_] := expr /. f_[xx___, arg, yy___] -> f[xx, yy];

(* build chebyshev grid *)
ChebyshevPoints[nz_, OptionsPattern["NumberOfDigits"->MachinePrecision]] := Block[{r, numberOfDigits},
	numberOfDigits = OptionValue["NumberOfDigits"];
	N[Table[Cos[(r \[Pi])/nz],{r,0,nz}], numberOfDigits]
];

ChebDerivMatrixDiag[nz_, chebyshevPoints_] :=
	Block[{firstDiag, lastDiag},
	firstDiag = (2(nz+1-1)^2+1)/6;
	lastDiag = -firstDiag;
	DiagonalMatrix[Join[{firstDiag}, Map[-#/(2(1-#^2))&, chebyshevPoints[[2;;-2]]], {lastDiag}]]
];

ChebDerivMatrixOffDiag[nz_, chebyshevPoints_] := Table[
	If[i!=j,(-1)^(i+j)/(chebyshevPoints[[i]]-chebyshevPoints[[j]]) If[i==1||i==nz+1,2,1]/If[j==1||j==nz+1,2,1],0],
	{i,nz+1},{j,nz+1}];

ChebyshevPointsIfNotGiven[nz_,chebPointsGiven_, numberOfDigits_:MachinePrecision] :=  If[TrueQ[chebPointsGiven], ChebyshevPoints[nz, "NumberOfDigits"->numberOfDigits], chebPointsGiven];

(* build derivative matrix for chebyshev grid *)
ChebDerivMatrix[nz_, OptionsPattern[{"ChebyshevPoints"->True,"NumberOfDigits"->MachinePrecision}]] := Block[
		{chebyshevPoints,firstDiag, lastDiag, diagMatrix,offDiag},

	chebyshevPoints = ChebyshevPointsIfNotGiven[nz, OptionValue["ChebyshevPoints"],
		OptionValue["NumberOfDigits"]];

	diagMatrix = ChebDerivMatrixDiag[nz, chebyshevPoints];
	offDiag = ChebDerivMatrixOffDiag[nz, chebyshevPoints];
	diagMatrix + offDiag
];

(* transform from [-1,1] to [a,b] *)
TransformChebIntervall[chebyshevPoints_, {a_,b_}] := chebyshevPoints*(a-b)/2+(a+b)/2;

(* transform from [-1,1] to [a,b] *)
TransformChebIntervall[chebyshevPoints_, {a_,b_}] := chebyshevPoints*(a-b)/2+(a+b)/2;
TransformDCheb[DCheb_, {a_, b_}] := DCheb*2/(a-b);

(* build cheby grid and derivative matrix returns {grid, matrix} *)
ChebyshevSetup[nz_, OptionsPattern[{"NumberOfDigits"->MachinePrecision, "Intervall"->{1,-1}}]]:=Block[
		{numberOfDigits, a,b, chebyshevPoints, DCheb},
	numberOfDigits = OptionValue["NumberOfDigits"];
	{a,b} = OptionValue["Intervall"];chebyshevPoints = ChebyshevPoints[nz, "NumberOfDigits"->numberOfDigits];DCheb =  ChebDerivMatrix[nz,"ChebyshevPoints"-> chebyshevPoints];
	If[{a,b}!={1,-1},
	chebyshevPoints = TransformChebIntervall[chebyshevPoints, {a,b}];
	DCheb = TransformDCheb[DCheb, {a,b}]];

	{chebyshevPoints, DCheb}
];

(* somehow SquareMatrix[m, 0] gives error when m singular, but should be identity *)
Unprotect[MatrixPower];
MatrixPower[m_?SquareMatrixQ, 0] := IdentityMatrix[Length@m];
Protect[MatrixPower];

BuildDEQMatrixOrderN[coeff_, x_, {grid_, deriv_}, order_] := Block[{},
	Print[coeff];
	If[FreeQ[coeff, x],
		coeff * MatrixPower[deriv, order],
		DiagonalMatrix[coeff/.x->grid].MatrixPower[deriv, order]
	]
];

(* given cheby derivative matrices and coefficients of the ODE, build operator L
	such that L f = c f *)
BuildDEQMatrixOperator[coeffs_, x_, {grid_,deriv_}] := Block[{nGrid, coeffsOnGrid, derivTerms, n},
	nGrid = Length@grid;
	DEQMatrixOperator = Sum[BuildDEQMatrixOrderN[coeffs[[n+1]], x, {grid, deriv}, n], {n,0,Length@coeffs-1}];
	DEQMatrixOperator
];

HasDerivQ[expr_] := Not@FreeQ[expr, Derivative];

(* ApplyDirichletBC (f[p] == y): not an easy task:
	- f[p] == y:
		- find grid point closest to p
		- set row in op corresponding to this grid point to be {0,...,1,0,0,...}
		- give a "source" term {0,...,y,0,0,...}
		- then op == source has f[p]==y as the row where p is
*)
ApplyDirichletBC[{DEQOperator_, source_}, bc_, {x_, x0_, x1_}] := Block[{operator, pos, f, p, nGrid},
	{pos, bcVal} = bc /. f_[p_] == y_ -> {p, y};
	nGrid = Length@DEQOperator;
	operator = DEQOperator;
	bcRow = Table[0, nGrid];
	rhs = source;

	If[Not@MemberQ[{x0,x1}, pos], Print["ERROR in ApplyDirichletBC, BC "<>ToString[bc]<>" is not at x0 or x1, this is not implemented yet!"]];

	If[pos == x0,
		rhs[[1]] = bcVal;
		bcRow[[1]] = 1;
		operator[[1]] = bcRow;
	];
	If[pos == x1,
		rhs[[-1]] = bcVal;
		bcRow[[-1]] = 1;
		operator[[-1]] = bcRow;
	];
	{operator, rhs}
]

(* f'[p] == y. Only works for one Neumann bc in the system, because it implements it always in row 2 *)
ApplyNeumannBC[{DEQOperator_, source_}, bc_, {x_, x0_, x1_}, derivMatrix_] := Block[{pos, bcVal, nGrid, operator, rhs},
	{pos, bcVal} = bc /. f_[p_] == y_ -> {p, y};
	nGrid = Length@DEQOperator;
	operator = DEQOperator;
	rhs = source;

	If[Not@MemberQ[{x0,x1}, pos], Print["ERROR in ApplyNeumannBC, BC "<>ToString[bc]<>" is not at x0 or x1, this is not implemented yet!"]];

	If[pos == x0,
		rhs[[2]] = bcVal;
		bcRow = derivMatrix[[1]];
		operator[[2]] = bcRow;
	];
	If[pos == x1,
		rhs[[2]] = bcVal;
		bcRow = derivMatrix[[-1]];
		operator[[2]] = bcRow;
	];

	{operator, rhs}
]

AddBoundaryCondition[{DEQOperator_, source_}, boundaryCondition_, {x_, x0_, x1_}, derivMatrix_] := Block[{operator, rhs},
	operator = DEQOperator;
	If[Not@HasDerivQ[boundaryCondition],
		{operator, rhs} = ApplyDirichletBC[{operator, source}, boundaryCondition, {x,x0,x1}];,
		{operator, rhs} = ApplyNeumannBC[{operator, source}, boundaryCondition, {x,x0,x1}, derivMatrix];];
	{operator, rhs}
];

(* assuming two boundary conditions, we only work with second order DEQs *)
AddBoundaryConditions[DEQOperator_, boundaryConditions_, fIndepTerm_, {x_, x0_, x1_}, derivMatrix_] := Block[
		{operator, rhs, rhs1, rhs2, source},
	operator = DEQOperator;

	If[Not@FreeQ[fIndepTerm, x],
		source = - fIndepTerm /. x->grid;,
		source = - fIndepTerm ConstantArray[1, Length@grid];
	];
	rhs = source;

	{operator, rhs} = AddBoundaryCondition[{operator, rhs}, boundaryConditions[[1]], {x,x0,x1}, derivMatrix];
	{operator, rhs} = AddBoundaryCondition[{operator, rhs}, boundaryConditions[[2]], {x,x0,x1}, derivMatrix];

	{operator, rhs}
];

ListDerivs[f_, x_, nMax_] := Map[Derivative[#][f][x]&, Range[0,nMax]];

(* only for up to second order ordinary linear DEQ *)
Options[ChebyNDSolveRaw] = {"GridPoints" -> 25, "NumberOfDigits"->MachinePrecision};
ChebyNDSolveRaw[DEQAndBCs__, f_, {x_,x0_,x1_}, OptionsPattern[]] := Block[
		{DEQ, BCs, fIndepTerm, nGrid, funcAndDerivs, coeffs, DEQMatrixOperator, rhsBcs, rhs, sol},
	DEQ = DEQAndBCs[[1]][[1]];
	BCs = DEQAndBCs[[2;;]];
	nGrid = OptionValue["GridPoints"];

	{grid, deriv} = ChebyshevSetup[nGrid, "Intervall"->{x0,x1}, "NumberOfDigits"->OptionValue["NumberOfDigits"]];
	funcAndDerivs = ListDerivs[f, x, 2]; (* f[x], f'[x], f''[x] *)
	coeffs = Coefficient[DEQ, funcAndDerivs];
	fIndepTerm = DEQ /.f->(0&);

	DEQMatrixOperator = BuildDEQMatrixOperator[coeffs, x, {grid,deriv}];
	{DEQMatrixOperator, rhsBcs} = AddBoundaryConditions[DEQMatrixOperator, BCs, fIndepTerm, {x,x0,x1}, deriv];
	sol = LinearSolve[DEQMatrixOperator, rhsBcs];
	{sol, grid}
];

Options[ChebyNDSolve] = {"GridPoints" -> 25, "NumberOfDigits"->MachinePrecision};
ChebyNDSolve[DEQAndBCs__, f_, {x_,x0_,x1_}, OptionsPattern[]] := Block[{sol, grid},
	{sol,grid} = ChebyNDSolveRaw[DEQAndBCs, f, {x,x0,x1},
		"GridPoints"->OptionValue["GridPoints"],
		"NumberOfDigits"->OptionValue["NumberOfDigits"]];
	Interpolation[Thread@{grid, sol}]
];


GetNthOrderTerm[DEQ_, f_, {x_, n_}] := Select[DEQ[[1]], Not[FreeQ[#, Derivative[n][f][x]]] &];


(* END OF FUNCTIONS *)

Scan[SetAttributes[#, {Protected, ReadProtected}]&,
     Select[Symbol /@ Names["NumericalPart`*"], Head[#] === Symbol &]];
EndPackage[];
