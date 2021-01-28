// Fluorescence section flipper
 
// Author: 	Luke Hammond (lh2881@columbia.edu)
// Cellular Imaging | Zuckerman Institute, Columbia University
// Date:	13th December 2017
//	
//	This macro vertically and horizontally flips sections and updates the section montage preview.
// 			
// 	Usage:
//		1. Run on folder containing ND2 files from AZ100 slide scanner after running Reformat Series
//		
// Version: 0.2
// Updates: V2 updated for new pipeline
// Updates: V3 temporary correction for repeated numbers
// 2/8/2017:v4 updated to export stacks, to improve memory handling for registering large datasets

// Initialization
starttime = getTime()
run("Clear Results"); 

#@ File(label="Select folder:", description="Folder containing brain data", style="directory") input
#@ string(label="Which sections require horizontal flipping? E.g. 1,4,6",  style="text field", value = "1,2,3", description="") HFlipNo
#@ string(label="Which sections require vertical flipping?",  style="text field", value = "", description="") VFlipNo
#@ string(label="Which sections require replacing? Section replaced with neighboring section.",  style="text field", value = "", description="") ReplaceNo
#@ String(label="Method for replacement:", choices={"Replace all channels", "Replace DAPI/registration channel, clear other channels"}, style="radioButtonHorizontal", value = "Replace all channels") Method

// Preparation
print("\\Clear");
print("Fluorescence section flipper/replacer running...");
print("");
setBatchMode(true);

// Read in parameters 
if (File.exists(input + "/Experiment_Parameters.csv")) {
		ParamFile = File.openAsString(input + "/Experiment_Parameters.csv");
		ParamFileRows = split(ParamFile, "\n"); 
	} else {
		exit("Experiment Parameter file doesn't exist, please run Setup Experiment Parameters step for this folder first");
	}

AlignCh = parseInt(LocateValue(ParamFileRows, "DAPI/Autofluorescence channel"));

// List preparation

HFlipIdx = num2array(HFlipNo,",");
VFlipIdx = num2array(VFlipNo,",");
ReplaceIdx = num2array(ReplaceNo,",");

if (HFlipIdx.length > 0){
	print("Horizontally flipping sections:");
	Array.print(HFlipIdx);
}
if (VFlipIdx.length > 0) {
	print("Vertically flipping sections:");
	Array.print(VFlipIdx);
}
if (ReplaceIdx.length > 0) {
	print("Replacing sections:");
	Array.print(ReplaceIdx);
}
print("");

// Find out how many channels:
input = input + "/";
Export = input + "1_Reformatted_Sections/";
ChNum = CountSubFolders(Export);
ChArray = NumberedArray(ChNum);

run("Collect Garbage");

// Process each channel
for(j=1; j<ChNum+1; j++) {		
	FileFolder = input + "1_Reformatted_Sections/"+(j)+"/";
	files = getFileList(FileFolder);
	files = Array.sort( files );
	print("Processing channel " + (j) +" of " + ChNum +".");
	//iterate over all files
	//Horizontally 
	for(i=0; i<HFlipIdx.length; i++) {				
		image = files[HFlipIdx[i]-1];
		print("Horizontally flipping sections...");
		print("\\Update:Horizontally flipping section " + (HFlipIdx[i]) +" of " + files.length +".");
		open(FileFolder + image);
		getDimensions(width, height, ChNumz, slices, frames);
		//run("Bio-Formats Importer", "open=["+ TIF_Export + image + "] autoscale color_mode=Composite view=Hyperstack stack_order=XYCZT");
		ok = File.delete(FileFolder + image);
		getPixelSize(unit, W, H);
		run("Flip Horizontally");
		//run("Save");
		saveAs("Tiff", FileFolder + image);
		close();
	}
	//Vertically
	for(i=0; i<VFlipIdx.length; i++) {				
		image = files[VFlipIdx[i]-1];	
		print("Vertically flipping sections...");
		print("\\Update:Vertically flipping section " + (VFlipIdx[i]) +" of " + files.length +".");
		open(FileFolder + image);
		getDimensions(width, height, ChNumz, slices, frames);
		//run("Bio-Formats Importer", "open=["+ TIF_Export + image + "] autoscale color_mode=Composite view=Hyperstack stack_order=XYCZT");
		ok = File.delete(FileFolder + image);
		getPixelSize(unit, W, H);
		run("Flip Vertically");
		//run("Save");
		saveAs("Tiff", FileFolder + image);
		close();
	}
	//Replacing
	for(i=0; i<ReplaceIdx.length; i++) {				
		print("Replacing sections...");
		print("\\Update:Replacing section " + (ReplaceIdx[i]) +" of " + files.length +".");	
		if (j == AlignCh || Method == "Replace all channels") {
			oldimage = files[ReplaceIdx[i]-1];	
			if (ReplaceIdx[i]-1 == 0) {
				newimage = files[ReplaceIdx[i]];
			} else {
				newimage =	files[ReplaceIdx[i]-2];
			}
			ok = File.delete(FileFolder + oldimage);
			ok = File.copy(FileFolder + newimage, FileFolder + oldimage);			
		} else {
			image = files[ReplaceIdx[i]-1];	
			open(FileFolder + image);
			ok = File.delete(FileFolder + image);
			run("Select All");
			run("Cut");
			run("Select None");
			saveAs("Tiff", FileFolder + image);
			close();	
		}
	}
run("Collect Garbage");
print("");
}
		
midendtime = getTime();
middif = (midendtime-starttime)/1000;
print("Section flipping complete. Processing time =", (middif/60), "minutes. ");
print("");
// Recreate montage and preview

DeleteDir(input +"2_Section_Preview/");
File.mkdir(input + "2_Section_Preview");

print("Creating scaled down stack for checking section quality and order..");
//setBatchMode(false);
run("Collect Garbage");

if (ChNum > 1) {
	for(j=1; j<ChArray.length+1; j++) {
		Export = input + "1_Reformatted_Sections/"+j+"/";
		previewfiles = getFileList(Export);
		previewfiles = Array.sort( previewfiles );
		len = previewfiles.length;
		previewimage = previewfiles[0];		
		downscale = 0.03;
		run("Image Sequence...", "open=["+ Export + previewimage + "] scale="+ downscale + " sort");
		rename("Raw-"+j);
		
		//Create Max and Measure intensities for rescaling preview
		run("Z Project...", "projection=[Max Intensity]");
		selectWindow("MAX_Raw-"+j);
		getRawStatistics(nPixels, mean, min, max, std, histogram);
		selectWindow("Raw-"+j);
		setMinAndMax(0, max);
		run("Apply LUT", "stack");
	}
} else {
	Export = input + "1_Reformatted_Sections/1/";
	previewfiles = getFileList(Export);
	previewfiles = Array.sort( previewfiles );
	len = previewfiles.length;
	previewimage = previewfiles[0];		
	downscale = 0.03;
	run("Image Sequence...", "open=["+ Export + previewimage + "] scale="+ downscale + " sort");
	rename("Raw-1");
	//Create Max and Measure intensities for rescaling preview
	run("Z Project...", "projection=[Max Intensity]");
	selectWindow("MAX_Raw-1");
	getRawStatistics(nPixels, mean, min, max, std, histogram);
	selectWindow("Raw-"+j);
	setMinAndMax(0, max);
	run("Apply LUT", "stack");
}

if (ChNum == 2){
	run("Merge Channels...", "c1=Raw-1 c2=Raw-2 create");
}
if (ChNum == 3){
	run("Merge Channels...", "c1=Raw-1 c2=Raw-2 c3=Raw-3 create");
}
if (ChNum == 4){
	run("Merge Channels...", "c1=Raw-1 c2=Raw-2 c3=Raw-3 c4=Raw-4 create");
}


input_ID = getImageID();

//make montage
run("Remove Slice Labels");	
run("Colors...", "foreground=white background=black selection=yellow");
File.mkdir(input + "2_Section_Preview");
sq = round(sqrt(len));
col = sq;
row = (sq+1);
run("Make Montage...", "columns="+col+" rows="+row+" scale=1 font=14 label use");
run("Make Composite", "display=Composite");
saveAs("Tiff", "" + input + "2_Section_Preview/Section_Preview_Montage.tif");
close();

// save stack preview
selectImage(input_ID); 
run("Re-order Hyperstack ...", "channels=[Channels (c)] slices=[Frames (t)] frames=[Slices (z)]");
run("Time Stamper", "starting=1 interval=1 x=1 y=16 font=14 decimal=0 anti-aliased or= ");
saveAs("Tiff", input + "2_Section_Preview/Section_Preview_Stack.tif");
close();

run("Collect Garbage");



endtime = getTime();
dif = (endtime-midendtime)/1000;
print("Section preivew montage complete. Generation time =", (dif/60), "minutes.");

selectWindow("Log");
saveAs("txt", input+"/Section_Flipper_and_Replacer_Log.txt");


function NumberedArray(maxnum) {
	//use to create a numbered array from 1 to maxnum, returns numarr
	//e.g. ChArray = NumberedArray(ChNum);
	numarr = newArray(maxnum);
	for (i=0; i<numarr.length; i++){
		numarr[i] = (i+1);
	}
	return numarr;
}



function DeleteDir(Dir){
	listDir = getFileList(Dir);
  	//for (j=0; j<listDir.length; j++)
      //print(listDir[j]+": "+File.length(myDir+list[i])+"  "+File. dateLastModified(myDir+list[i]));
 // Delete the files and the directory
	for (j=0; j<listDir.length; j++)
		ok = File.delete(Dir+listDir[j]);
	ok = File.delete(Dir);
	//if (File.exists(Dir))
	   // print("\\Update10: Unable to delete temporary directory"+ Dir +".");
	//else
	    //print("\\Update10: Temporary directory "+ Dir +" and files successfully deleted.");
}


function num2array(str,delim){
	arr = split(str,delim);
	for(i=0; i<arr.length;i++) {
		arr[i] = parseInt(arr[i]);
	}

	return arr;
}		

function CountSubFolders(Directory) {
	// 
	SubFolders = getFileList(Directory);
	SubFolderCount = 0;
	for(i=0; i<SubFolders.length; i++) { 
		if (File.isDirectory(Directory+SubFolders[i])) {
			SubFolderCount = SubFolderCount + 1;
		}
	}
	return SubFolderCount;
}

function LocateValue(inputArray, VarName) {
		
	//Give array name, and variable name in column 0, returns value in column 1
	Found = 0;
	for(i=0; i<inputArray.length; i++){ 
		if(matches(inputArray[i],".*"+VarName+".*") == 1 ){
			Row = split(inputArray[i], ",");
			Value = Row[1];
			Found = 1; 	
		}
		
	}
	if (Found == 0) {
		Value = 0;
	}
	return Value;
}

