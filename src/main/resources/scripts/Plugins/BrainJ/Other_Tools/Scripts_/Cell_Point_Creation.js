
importClass(Packages.ij.IJ);
importClass(Packages.ij.measure.ResultsTable)
importClass(Packages.ij.gui.Roi);
importClass(Packages.ij.gui.OvalRoi);
importClass(Packages.ij.measure.Measurements);
importClass(Packages.ij.gui.GenericDialog);


//construct the dialog
gd = new GenericDialog("Options");
gd.addStringField("Select experiment/brain folder: ", "brain folder");
gd.addStringField("Select output folder: ", "output folder");
gd.addNumericField("Cell channel: ", 1, 0);
gd.addNumericField("AtlasSizeX: ", 512, 0);
gd.addNumericField("AtlasSizeY: ", 512, 0);
gd.addNumericField("AtlasSizeZ: ", 512, 0);
gd.showDialog();

if (!gd.wasCanceled()) {
	input = gd.getNextString();
	output = gd.getNextString();
	CellChan = gd.getNextNumber();
	AtlasSizeX = gd.getNextNumber();
	AtlasSizeY = gd.getNextNumber();
	AtlasSizeZ = gd.getNextNumber();
      
}
//Get Arguments from the macro
//InputArgs = getArgument();
//InputArgs = InputArgs.split(",");

// Information for creating the heatmap
//runMacro("/Users/lukehammond/Desktop/Heatmap_Creation_5_5px_Args.js", input+", "+output+", "+CellChan+", "+AtlasSizeX+", "+AtlasSizeY+", "+AtlasSizeZ);

//var start = new Date().getTime();

i = CreateCellPointsJS(CellChan);

//var end = new Date().getTime();
//var time = end - start;
IJ.log('   Total points plotted: ' + i);
//IJ.log('Execution time: ' + time);

function CreateCellPointsJS(CellChan) {
	//IJ.log("  Creating cell heatmaps for channel "+CellChan+" ...");
	
	rt = ResultsTable.open(input + "5_Analysis_Output/Cell_Analysis/C"+CellChan+"_Detected_Cells.csv");
	ChCount = rt.getCounter();

	imp = IJ.createImage("Cells", "8-bit black", AtlasSizeX, AtlasSizeY, AtlasSizeZ);
	ip = imp.getProcessor();

	for (var i = 0; i < ChCount; i++) {
		var RegionIDCheck = rt.getStringValue("ID", i);
		if (RegionIDCheck >0) {
			var X = rt.getStringValue("X", i);
			var Y = rt.getStringValue("Y", i);
			var Z = rt.getStringValue("Z_Dither", i);
			
			if (Z <= AtlasSizeZ) {
				Intensity=255;
				imp.setSlice(Z);
				imp.setRoi(X,Y,1,1);
				ip.add(Intensity);
			}
		}
	}
	IJ.run(imp, "Select None", "");
	IJ.saveAsTiff(imp, output + "C"+CellChan+"_Cell_Points.tif");
	return i;

}

