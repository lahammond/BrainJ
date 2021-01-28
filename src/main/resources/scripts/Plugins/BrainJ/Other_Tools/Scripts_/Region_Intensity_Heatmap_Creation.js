importClass(Packages.ij.IJ);
importClass(Packages.ij.measure.ResultsTable)
importClass(Packages.ij.gui.Roi);
importClass(Packages.ij.gui.OvalRoi);
importClass(Packages.ij.measure.Measurements);
importClass(Packages.ij.gui.GenericDialog);
importClass(Packages.ij.plugin.ImageCalculator);



//construct the dialog
gd = new GenericDialog("Options");
gd.addStringField("Select experiment/brain folder: ", "brain folder");
gd.addStringField("Select output folder: ", "output folder");
gd.addStringField("Select atlas folder: ", "atlas folder");
gd.addNumericField("Cell channel: ", 1, 0);
gd.addNumericField("Projection Analysis Resolution: ", 25, 0);
gd.addNumericField("AtlasSizeX: ", 512, 0);
gd.addNumericField("AtlasSizeY: ", 512, 0);
gd.addNumericField("AtlasSizeZ: ", 512, 0);
gd.showDialog();

if (!gd.wasCanceled()) {
	input = gd.getNextString();
	output = gd.getNextString();
	AtlasDir = gd.getNextString();
	Chan = gd.getNextNumber();
	ProAnRes = gd.getNextNumber();
	AtlasSizeX = gd.getNextNumber();
	AtlasSizeY = gd.getNextNumber();
	AtlasSizeZ = gd.getNextNumber();
      
}

//TestParameters
//input = "C:/Users/Luke/Desktop/Home Analysis Testing/BrainJ Test Data/";
//output = input + "5_Analysis_Output/Region_Mean_Intensity_Measurements_25_micron/"
//AtlasDir = "C:/Users/Luke/Desktop/Home Analysis Testing/BrainJ Atlases/ABA_CCF_25_2017_Coronal/"
//Chan = 1;
//AtlasSizeX=456;
//AtlasSizeY=320;
//AtlasSizeZ=528;


//var start = new Date().getTime();

CreateRegionIntensityHeatmapJS(Chan);

//var end = new Date().getTime();
//var time = end - start;
//IJ.log('   Total spheres created: ' + i);
//IJ.log('Execution time: ' + time);

function CreateRegionIntensityHeatmapJS(Chan) {
	//IJ.log("  Creating cell heatmaps for channel "+CellChan+" ...");
	
	// Create empty image for heatmap - Created as sagittal - hence Z,Y,X - reslice at end for coronal
	
	imp = IJ.createImage("Heatmap", "16-bit black", AtlasSizeZ, AtlasSizeY, AtlasSizeX);
	ip = imp.getProcessor();
	
	
	rt = ResultsTable.open(output+"/C"+Chan+"_Measured_Region_Intensity.csv");
	Count = rt.getCounter();
	

	for (var i = 0; i < Count; i++) {
		var RegionID = rt.getStringValue("ID", i);
		if (RegionID >0) {
			var RegionIntensityLeft = rt.getStringValue("Mean_Intensity_Left", i);
			var RegionIntensityRight = rt.getStringValue("Mean_Intensity_Right", i);
			if (RegionIntensityLeft > 0 || RegionIntensityRight > 0 ) {
				imp2 = IJ.openImage(AtlasDir+"/Region_Masks/structure_"+RegionID+".nrrd");
				IJ.run(imp2, "16-bit", "");
				ip2 = imp2.getProcessor();
				
				//Fill Left Side
				for (slice=AtlasSizeX/2+1; slice<=AtlasSizeX; slice++) { 
	  				imp2.setSlice(slice);
	  				ip2.multiply(RegionIntensityLeft);
				}
				//Process Right Side
				for (slice=1; slice<=AtlasSizeX/2; slice++) { 
	  				imp2.setSlice(slice);
	  				ip2.multiply(RegionIntensityRight);
				}

				ic = new ImageCalculator();
 				imp = ic.run("Add create stack", imp, imp2)
 				imp2.close();
   				//imp.show();
			}
		}
	
		if (i == parseInt(Count/4)) {
			IJ.log("     25% complete...");
		}
		if (i == parseInt(Count/2)) {
			IJ.log("\\Update:     50% complete...");
		}
		if (i == parseInt(Count/4*3)) {
			IJ.log("\\Update:     75% complete...");
		}
	}
				
	IJ.run(imp, "Fire", "");
	//imp3 = IJ.run(imp, "Reslice [/]...", "output=1.000 start=Left rotate avoid");
	IJ.saveAsTiff(imp, output + "/C"+Chan+"_Region_Intensity_Heatmap.tif");
	imp.close(); 
	//imp3.close(); 
	//IJ.run("Collect Garbage", "");
	//IJ.run("Collect Garbage", "");
				
	//return i;

}


