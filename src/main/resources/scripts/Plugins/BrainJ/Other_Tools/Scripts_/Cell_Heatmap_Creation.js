// Sphere creation
 
// Author: 	Luke Hammond (lh2881@columbia.edu)
// Cellular Imaging | Zuckerman Institute, Columbia University
// Date:	10th December 2019
//	
//	This script creates spheres in javascript to greatly increase speed for processing millions of cells.
// 	Since sphere creation generates boxes, spheres are created through rectangular components


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

i = CreateCellHeatmapJS(CellChan);

//var end = new Date().getTime();
//var time = end - start;
IJ.log('   Total spheres created: ' + i);
//IJ.log('Execution time: ' + time);

function CreateCellHeatmapJS(CellChan) {
	//IJ.log("  Creating cell heatmaps for channel "+CellChan+" ...");
	
	rt = ResultsTable.open(input + "5_Analysis_Output/Cell_Analysis/C"+CellChan+"_Detected_Cells.csv");
	ChCount = rt.getCounter();

	imp = IJ.createImage("Cells", "16-bit black", AtlasSizeX, AtlasSizeY, AtlasSizeZ);
	ip = imp.getProcessor();

	for (var i = 0; i < ChCount; i++) {
		var RegionIDCheck = rt.getStringValue("ID", i);
		if (RegionIDCheck >0) {
			var X = rt.getStringValue("X", i);
			var Y = rt.getStringValue("Y", i);
			var Z = rt.getStringValue("Z_Dither", i);
			
			if (Z <= (AtlasSizeZ-6)) {
				Intensity=1;
				Create5_5pxRadiusSphere(parseInt(X), parseInt(Y), parseInt(Z));				
			}
		}
	}
	IJ.run(imp, "Select None", "");
	IJ.saveAsTiff(imp, output + "C"+CellChan+"_Cells_Heatmap.tif");
	return i;

}

function Create5_5pxRadiusSphere(X,Y,Z){

	imp.setSlice(Z-5);
	AddValueToRegion(X-2,Y-1,5,3);
	AddValueToRegion(X-1,Y-2,3,1);
	AddValueToRegion(X-1,Y+2,3,1);

	imp.setSlice(Z-4);
	AddValueToRegion(X-2,Y-3,5,1);
	AddValueToRegion(X-3,Y-2,7,5);
	AddValueToRegion(X-2,Y+3,5,1);
	
	imp.setSlice(Z-3);
	AddValueToRegion(X-2,Y-4,5,1);
	AddValueToRegion(X-3,Y-3,7,1);
	AddValueToRegion(X-4,Y-2,9,5);
	AddValueToRegion(X-3,Y+3,7,1);
	AddValueToRegion(X-2,Y+4,5,1);
	
	imp.setSlice(Z-2);
	AddValueToRegion(X-1,Y-5,3,1);
	AddValueToRegion(X-3,Y-4,7,1);
	AddValueToRegion(X-4,Y-3,9,2);
	AddValueToRegion(X-5,Y-1,11,3);
	AddValueToRegion(X-4,Y+2,9,2);
	AddValueToRegion(X-3,Y+4,7,1);
	AddValueToRegion(X-1,Y+5,3,1);
	
	imp.setSlice(Z-1);
	AddValueToRegion(X-2,Y-5,5,1);
	AddValueToRegion(X-3,Y-4,7,1);
	AddValueToRegion(X-4,Y-3,9,1);
	AddValueToRegion(X-5,Y-2,11,5);
	AddValueToRegion(X-4,Y+3,9,1);
	AddValueToRegion(X-3,Y+4,7,1);
	AddValueToRegion(X-2,Y+5,5,1);
	
	imp.setSlice(Z);
	AddValueToRegion(X-2,Y-5,5,1);
	AddValueToRegion(X-3,Y-4,7,1);
	AddValueToRegion(X-4,Y-3,9,1);
	AddValueToRegion(X-5,Y-2,11,5);
	AddValueToRegion(X-4,Y+3,9,1);
	AddValueToRegion(X-3,Y+4,7,1);
	AddValueToRegion(X-2,Y+5,5,1);

	imp.setSlice(Z+1);
	AddValueToRegion(X-2,Y-5,5,1);
	AddValueToRegion(X-3,Y-4,7,1);
	AddValueToRegion(X-4,Y-3,9,1);
	AddValueToRegion(X-5,Y-2,11,5);
	AddValueToRegion(X-4,Y+3,9,1);
	AddValueToRegion(X-3,Y+4,7,1);
	AddValueToRegion(X-2,Y+5,5,1);
	
	imp.setSlice(Z+2);
	AddValueToRegion(X-1,Y-5,3,1);
	AddValueToRegion(X-3,Y-4,7,1);
	AddValueToRegion(X-4,Y-3,9,2);
	AddValueToRegion(X-5,Y-1,11,3);
	AddValueToRegion(X-4,Y+2,9,2);
	AddValueToRegion(X-3,Y+4,7,1);
	AddValueToRegion(X-1,Y+5,3,1);
	
	imp.setSlice(Z+3);
	AddValueToRegion(X-2,Y-4,5,1);
	AddValueToRegion(X-3,Y-3,7,1);
	AddValueToRegion(X-4,Y-2,9,5);
	AddValueToRegion(X-3,Y+3,7,1);
	AddValueToRegion(X-2,Y+4,5,1);
	
	imp.setSlice(Z+4);
	AddValueToRegion(X-2,Y-3,5,1);
	AddValueToRegion(X-3,Y-2,7,5);
	AddValueToRegion(X-2,Y+3,5,1);

	imp.setSlice(Z+5);
	AddValueToRegion(X-1,Y-2,3,1);
	AddValueToRegion(X-2,Y-1,5,3);
	AddValueToRegion(X-1,Y+2,3,1);
}

function AddValueToRegion(sX, sY, sW, sH){
	//requires global intensity set first
	imp.setRoi(sX,sY,sW,sH);
	ip.add(Intensity);
	
}


