// Imaris Image Importer for BrainJ
 
// Author: 	Luke Hammond (lh2881@columbia.edu)
// Zuckerman Institute, Columbia University
// Date:	30th September 2019
//	
//	Import IMS file and put into BrainJ Folder Structure
//		Meant for projects where cells have been counted manually in Imaris and registration needs to be performed subsquently
// 			
// 	Usage:
//		1. Select IMS file, set resolution, and set Brain Folder - create folders as necessary
//
// Updates:
// 
//
// Initialization
run("Colors...", "foreground=white background=black selection=yellow");
run("Options...", "iterations=1 count=1 black do=Nothing");
run("Clear Results"); 
CloseOpenWindows();


// Select input directories
//https://imagej.net/Script_Parameters

#@ File[](label="Select .IMS file/s for conversion:", style="file") IMS_Files
#@ File(label="Select output directory (a subfolder will be made for each .ims file/brain):", style="directory") OutputDir
#@ String(label="Set input resolution (X, Y, Z)", value = "1.626, 1.626, 3.5", style="text field", description=".") InputRes
#@ String(label="Set output resolution (X, Y, Z)", value = "25, 25, 25", style="text field", description=".") OutputRes
#@ String (visibility=MESSAGE, value="The ABA template brain is oriented such that the AP axis = X, DV = Y, and ML = Z. Use the field below to desribe the orientation of the imaged brain.") docms
#@ String(label="Image Orientation (Provide the orientation of X, Y and Z in the image):", value = "DV, AP, ML", style="text field", description="AP should be X axis, DV should be Y axis, ML should be Z axis.") Orientation
#@ Boolean(label="Flip horizontally? (Is dorsal surface at top, or left, of image? If not, flip.", value = "true", description="Dorsal surface of brain should be at top or left of image.") Flip
#@ Integer(label="Channel used for registration (DAPI / Autofluorescence):", value = 1, style="spinner", description=".") RegCh

setBatchMode(true);

starttime = getTime();

print("\\Clear");
print("\\Update0:Convertering .IMS files for registration in BrainJ");

// Convert resolutions into arrays
InputResArr = num2array(InputRes,",");
OutputResArr = num2array(OutputRes,",");
//OrientationArr = num2array(Orientation,",");
Orientation = replace(Orientation, " ", "");
OrientationArr = split(Orientation,",");

// Find the lowest resolution in the input
Array.getStatistics(InputResArr, min, max, mean, std);
// Determine the pyramid resolution we can import the IMS file at before further downscaling
max_scaleup = max;
for (i = 2; i < 6; i++) {
	if (25 / (max_scaleup * 2) >= 1) {
		ImportRes = i;
	}
	max_scaleup = max_scaleup*2;
}

// Calculate Imported Res
ImportX = InputResArr[0];
ImportZ = InputResArr[2];
for (i = 1; i < ImportRes; i++) {
	ImportX = ImportX * 2;
	ImportZ = ImportZ * 2;
}


// Calculate Rescale values 1 / (Final Res / Imported Image Res)
	RescaleXY = ImportX / OutputResArr[0];
	RescaleZ = ImportZ / OutputResArr[0];


OutputDir = OutputDir + "/";

for (F = 0; F < IMS_Files.length; F++) {
	
	print("\\Update1:Convertering file "+F+1+" of "+IMS_Files.length+". Imaris file: "+IMS_Files[F]+" for registration in BrainJ");

	// print out the pyramid number and the resolution IMS file will be imported at

	print("\\Update3:Full resolution of .ims file is "+InputResArr[0]+", "+InputResArr[1]+", "+InputResArr[2]+" micron.");
	print("\\Update4:Orientation of image was:"+Orientation+". Flip was set to: "+Flip+".");

	print("\\Update5:Importing .ims image pyradmid "+ImportRes+" of 6.");
	print("\\Update6:This image has a resolution of "+ImportX+", "+ImportX+", "+ImportZ+" micron.");
	print("\\Update7:Rescaling to "+OutputResArr[0]+" isotropic and saving to : "+ OutputDir);

	
	// import the data
	run("Bio-Formats", "open=["+IMS_Files[F]+"]" +
		"autoscale color_mode=Default rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT series_"+ImportRes+"");

	//Create Output folder

	filename1 = split(IMS_Files[F], "\\");
	FileName = filename1[lengthOf(filename1)-1];
	BrainOut = clean_title(FileName);
	
	File.makeDirectory(OutputDir + BrainOut);
	BrainDir = OutputDir + BrainOut;
	File.makeDirectory(BrainDir + "/3_Registered_Sections");
	RegOut = BrainDir + "/3_Registered_Sections/";

	// Process image

	rename("Input_Image");
	
	// In case resolution not actually saved with IMS - apply it now:
	run("Properties...", "unit=micron pixel_width="+ImportX+" pixel_height="+ImportX+" voxel_depth="+ImportZ+"");
	
	//Rescale Image
	run("Scale...", "x="+RescaleXY+" y="+RescaleXY+" z="+RescaleZ+" interpolation=Bilinear average create");
	// apply properties - z is sometimes incorrect, and round values to integers.
	run("Properties...", "unit=micron pixel_width=25 pixel_height=25 voxel_depth=25");
	
	rename("Scaled_Image");
	close("Input_Image");

	selectWindow("Scaled_Image");

	save(RegOut + "Original_OrientationDAPI.tif");
	
	if (Flip == true) {
		run("Flip Horizontally", "stack");
	}
	if (OrientationArr[0] == "DV" && OrientationArr[1] == "AP") {
		run("Rotate 90 Degrees Right");
	}
	
	// split channels and save
	// Had to use export function as normal tif saving was creating errors in other program. saved as 3 channels when only one
	// related to splitting file in bioformats.
	
	getDimensions(width, height, channels, slices, frames);
	
	run("Split Channels");
	
	selectWindow("C"+RegCh+"-Scaled_Image");
	run("Subtract Background...", "rolling=100 sliding stack");
	run("Z Project...", "projection=[Max Intensity]");
	getStatistics(area, mean, min, max, std, histogram);
	setMinAndMax(min,max);
	run("Apply LUT");
	setAutoThreshold("Triangle dark");
	cleanupROI();

	run("Set Measurements...", "centroid bounding redirect=None decimal=0");
	run("Analyze Particles...", "size=10000000-Infinity add");
	roiManager("Save", BrainDir +"/BrainROI.zip");
	roiManager("Select", 0);	
	run("Measure");
	TOPX = getResult("BX", 0)/25;
	TOPY = getResult("BY", 0)/25;
	
	// May need to set something that merges multiple regions if brain is very dim and fragmented
	//but for now just find objects roughly size of brain
	close("MAX_C"+RegCh+"-Scaled_Image");
	
	selectWindow("C"+RegCh+"-Scaled_Image");
	roiManager("Select", 0);
	run("Crop");
	getDimensions(newwidth, newheight, dummy, dummy, dummy);
	run("Clear Outside", "stack");
	setMinAndMax(min,max);
	run("Apply LUT", "stack");
	run("Unsharp Mask...", "radius=1 mask=0.60 stack");
	
	
	// to fix libtiff color import issue into elastix remove color
	run("Grays");
	run("Remove Slice Labels");
	run("Select None");
	save(RegOut + "Sagittal25DAPI.tif");
	roiManager("Select", 0);
	run("Fill", "stack");
	run("Select None");
	run("Clear Results");
	roiManager("Delete");
	//run("Convert to Mask", "method=Triangle background=Dark black");
	save(RegOut + "Sagittal25DAPI_Mask.tif");
	close("C"+RegCh+"-Scaled_Image");
	
	for (i = 1; i <= channels; i++) {
		if (i != RegCh) {
			selectWindow("C"+i+"-Scaled_Image");
			roiManager("Open",  BrainDir +"/BrainROI.zip");
			roiManager("Select", 0);
			run("Crop");
			run("Clear Results");
			roiManager("Delete");
			run("Remove Slice Labels");
			run("Grays");
			run("Select None");
			save(RegOut + "C"+i+"_Sagittal.tif");
			close("C"+i+"-Scaled_Image");
		}
		
	}
	run("Close All");

// Create an appropriate "Experiment_Parameters File"

	title1 = "Brain_Parameters"; 
	title2 = "["+title1+"]"; 
	f=title2; 
	run("New... ", "name="+title2+" type=Table"); 
	print(f,"\\Headings:Parameter\tValue");

	
	print(f,"Directory:\tIMS"); //0
	print(f,"Sample Type:\tLight Sheet"); //1
	print(f,"Rotation:\tx"); //3
	print(f,"Flip:\tx"); //4
	print(f,"Slice Arrangement:\tLight Sheet"); //5
	print(f,"Final Resolution:\t"+InputResArr[0]); //6
	print(f,"Section cut thickness:\t"+InputResArr[2]); //7
	
	print(f,"DAPI/Autofluorescence channel:\t"+RegCh); //8
	
	print(f,"DAPI/Autofluorescence background intensity:\t200"); //9
	print(f,"File Ordering:\tLight Sheet"); //10
	print(f,"Input Image Type:\tLight Sheet"); //11
	
	print(f,"Analysis Type:\tWhole Brain"); //12	
	//print(f,"ABA Region Numbers:\t"+RegionNumbers); 	
	//print(f,"AtlasDir:\t"+AtlasDir); 
	
	print(f,"Input Resolution:\t"+InputResArr[1]); //13
	print(f,"LS Orientation:\t\""+Orientation+"\""); //14
	print(f,"LS Flip:\t"+Flip); //14
	print(f,"LS Crop X :\t"+TOPX); //15
	print(f,"LS Crop Y:\t"+TOPY); //16
	print(f,"LS Crop NewWidth:\t"+width); //16
	print(f,"LS Crop NewHeight:\t"+height); //16
	
	
		
	selectWindow(title1);	
	saveAs("txt", BrainDir + "/Experiment_Parameters.csv");
	selectWindow("Log");
	saveAs("txt", BrainDir + "/IMS_conversion_log.txt");
	closewindow(title1);
	DeleteFile( BrainDir + "/BrainROI.zip");


}
print("\\Update10:*** Conversion complete ***");


///////////// FUNCTIONS /////////////////////////


function num2array(str,delim){
	arr = split(str,delim);
	for(i=0; i<arr.length;i++) {
		arr[i] = parseFloat(arr[i]);
	}

	return arr;
}	


function clean_title(imagename){
	new = split(imagename, "/");
	if (new.length > 1) {
		imagename = new[new.length-1];
	} 
	nl=lengthOf(imagename);
	nl2=nl-4;
	Sub_Title=substring(imagename,0,nl2);
	Sub_Title = replace(Sub_Title, "(", "_");
	Sub_Title = replace(Sub_Title, ")", "_");
	Sub_Title = replace(Sub_Title, "-", "_");
	Sub_Title = replace(Sub_Title, "+", "_");
	Sub_Title = replace(Sub_Title, " ", "_");
	Sub_Title = replace(Sub_Title, "%", "_");
	Sub_Title = replace(Sub_Title, "&", "_");
	return Sub_Title;
}



function closewindow(windowname) {
	if (isOpen(windowname)) { 
      		 selectWindow(windowname); 
       		run("Close"); 
  		} 
}

function CloseOpenWindows(){
	listwindows = getList("image.titles");
	if (listwindows.length > 0) {
		for (list=0; list<listwindows.length; list++) {
		selectWindow(listwindows[list]);
		close();
		}
	}
}

function cleanupROI() {
	CountROImain=roiManager("count"); 
		if (CountROImain == 1) {
			roiManager("delete");
			CountROImain=0;
		} else if (CountROImain > 1) {
			ROIarrayMain=newArray(CountROImain); 
			for(n=0; n<CountROImain;n++) { 
	       		ROIarrayMain[n] = n; 
				} 
			roiManager("Select", ROIarrayMain);
			roiManager("Combine");
			roiManager("Delete");
			ROIarrayMain=newArray(0);
			CountROImain=0;
		}		
}

function DeleteFile(Filelocation){
	if (File.exists(Filelocation)) {
		a=File.delete(Filelocation);
	}
}
