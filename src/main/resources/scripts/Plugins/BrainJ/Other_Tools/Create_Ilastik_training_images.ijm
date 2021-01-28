// Training Image Creation
 
// Author: 	Luke Hammond (lh2881@columbia.edu)
// Cellular Imaging | Zuckerman Institute, Columbia University
// Date:	10th December 2019
//	
//	This macro creates background subtracted images based on the analysis settings
// 		ready to be used by ilastik for training

// Initialization
starttime = getTime()
run("Clear Results"); 

#@ File(label="Select folder:", description="Folder containing brain data", style="directory") input
#@ string(label="Which sections would you like to use for training Ilastik? E.g. 10,25,50",  style="text field", value = "1,2,3", description="") IlastikNo

// Preparation
print("\\Clear");
print("Creating Ilastik training images...");
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

if (File.exists(input + "/Analysis_Settings.csv")) {
     ParamFile = File.openAsString(input + "/Analysis_Settings.csv");
	 ParamFileRows = split(ParamFile, "\n"); 
		
	} else {
		exit("Analysis Settings file doesn't exist, please run Setup Experiment Parameters step for this folder first");
	}

	// Get Analysis Settings 

	BGSZ = parseInt(LocateValue(ParamFileRows, "Cell Analysis BG Subtraction"));
	CellDetMethod = LocateValue(ParamFileRows, "Cell Detection Type");
	CellCh = parseInt(LocateValue(ParamFileRows, "Cell Analysis 1"));
	CellCh2 = parseInt(LocateValue(ParamFileRows, "Cell Analysis 2"));
	CellCh3 = parseInt(LocateValue(ParamFileRows, "Cell Analysis 3"));
	CellChans = newArray(CellCh,CellCh2,CellCh3);

	ProjDetMethod = LocateValue(ParamFileRows, "Projection Detection Type");
	ProCh = parseInt(LocateValue(ParamFileRows, "Projection Analysis 1"));
	ProCh2 = parseInt(LocateValue(ParamFileRows, "Projection Analysis 2"));
	ProCh3 = parseInt(LocateValue(ParamFileRows, "Projection Analysis 3"));
	ProChans = newArray(ProCh,ProCh2,ProCh3);


// List preparation

ImageIdx = num2array(IlastikNo,",");

if (ImageIdx.length > 0){
	print("Creating preprocessed images for Ilastik training on sections:");
	Array.print(ImageIdx);
}
print("");

// Find out how many channels:
input = input + "/";
RawData = input + "1_Reformatted_Sections/";
File.makeDirectory(input + "Ilastik_Training_Images");
DataOut = input + "Ilastik_Training_Images/";


run("Collect Garbage");

//Process cell channels
for (Ch_i = 0; Ch_i < 3; Ch_i++) {
	if (CellChans[Ch_i] > 0) {
		File.makeDirectory(DataOut + CellChans[Ch_i]);
		FileFolder = input + "1_Reformatted_Sections/"+CellChans[Ch_i]+"/";
		files = getFileList(FileFolder);
		files = Array.sort( files );
		print("Processing channel " + CellChans[Ch_i]);
		for(i=0; i<ImageIdx.length; i++) {
			print("Processing sections...");
			print("\\Update: Processing section: " + ImageIdx[i]);
			image = files[ImageIdx[i]-1];
			open(FileFolder + image);
			run("Subtract Background...", "rolling="+ BGSZ);
			run("Grays");
			saveAs("Tiff", DataOut + CellChans[Ch_i] +"/"+ image);
		}
	}	
} 
for (Ch_i = 0; Ch_i < 3; Ch_i++) {
	if (ProChans[Ch_i] > 0) {
		if (File.exists(DataOut + ProChans[Ch_i]) == 0) {
			File.makeDirectory(DataOut + ProChans[Ch_i]);
			FileFolder = input + "1_Reformatted_Sections/"+ProChans[Ch_i]+"/";
			files = getFileList(FileFolder);
			files = Array.sort( files );
			print("Processing channel " + ProChans[Ch_i]);
			for(i=0; i<ImageIdx.length; i++) {
				print("Processing sections...");
				print("\\Update: Processing section: " + ImageIdx[i]);
				image = files[ImageIdx[i]-1];
				open(FileFolder + image);
				run("Subtract Background...", "rolling="+ BGSZ);
				saveAs("Tiff", DataOut + ProChans[Ch_i] +"/"+ image);
			}
		}
	}	
} 


run("Collect Garbage");
print("");
		
midendtime = getTime();
middif = (midendtime-starttime)/1000;
print("Image creation complete. Processing time =", (middif/60), "minutes. ");


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

	for (j=0; j<listDir.length; j++)
		ok = File.delete(Dir+listDir[j]);
	ok = File.delete(Dir);

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

