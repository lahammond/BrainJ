num = nResults;

for (i = 0; i < nResults; i++) {
	X = getResult("C1", i);
	Y = getResult("C2", i);
	Z = getResult("C3", i);
	setSlice(Z);
	makePoint(X, Y, "medium yellow hybrid");
	roiManager("add")
}
