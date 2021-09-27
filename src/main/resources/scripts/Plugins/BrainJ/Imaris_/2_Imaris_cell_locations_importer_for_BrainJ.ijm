// Imaris CSV importer for BrainJ
 
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
run("Clear Results"); 
CloseOpenWindows();


// Select input directories
//https://imagej.net/Script_Parameters

#@ File(label="Select .csv file containing cell locations for channel 1:", value = " ", style="file") CellsC1
#@ File(label="Select .csv file containing cell locations for channel 2:", value = " ", style="file") CellsC2
#@ File(label="Select .csv file containing cell locations for channel 3:", value = " ", style="file") CellsC3
#@ File(label="Select brain folder:", style="directory") OutputDir
#@ String(label="Resolution used when counting in Imaris (X, Y, Z)", value = "1, 1, 1", style="text field", description=".") InputResCells

// Flipping and orientation checked for DV, AP, ML to AP, DV, ML. Not working for others
run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file");

AtlasRes = 25;

setBatchMode(true);

starttime = getTime();

print("\\Clear");
print("\\Update0:Convertering .csv files from Imaris for registration in BrainJ");


if (File.exists(OutputDir + "/Experiment_Parameters.csv")) {
   	open(OutputDir + "/Experiment_Parameters.csv");
   	Table.rename(Table.title, "Results");
} else {
	exit("Experiment Parameter file doesn't exist, please run Setup Experiment Parameters step for this folder first");
}

//must select results table for reliabilty in newer versions of imagej
selectWindow("Results");
OutputRes = getResult("Value", 5);
XYRes = getResult("Value", 12);
ZRes = getResult("Value", 6);
Orientation = getResultString("Value", 13);
Flip = getResult("Value", 14);
TOPX = getResult("Value", 15);
TOPY = getResult("Value", 16);
Width = getResult("Value", 17);
Height = getResult("Value", 18);


ResampleX = XYRes/AtlasRes;
ResampleY = XYRes/AtlasRes;
ResampleZ = ZRes/AtlasRes;

print("Input resolution: "+XYRes+" "+ XYRes+" "+ZRes+". Atlas resolution:" +AtlasRes+". Resample factor: " + ResampleX +", " + ResampleY +", " + ResampleZ +".");

close("Results");
//orientation to array
//OrientationArr = num2array(Orientation,",");
Orientation = replace(Orientation, " ", "");
OrientationArr = split(Orientation,",");

InputResArr = num2array(InputResCells, ",");

// Create folder structure

File.makeDirectory(OutputDir + "/4_Processed_Sections");
File.makeDirectory(OutputDir + "/4_Processed_Sections/Detected_Cells");
File.makeDirectory(OutputDir + "/4_Processed_Sections/Resampled_Cells");
CellsOut1 = OutputDir + "/4_Processed_Sections/Detected_Cells/";
CellsOut2 = OutputDir + "/4_Processed_Sections/Resampled_Cells/";

// Process Cell Images:

if (endsWith(CellsC1, ".csv") == true) {
	print("Processing Cell Points file 1");
	IMStoBrainJCells(CellsC1, 1);
	print("Channel 1 complete.");
}

if (endsWith(CellsC2, ".csv") == true) {
	print("Processing Cell Points file 2");
	IMStoBrainJCells(CellsC2, 2);
	print("Channel 2 complete.");
}
if (endsWith(CellsC3, ".csv") == true) {
	print("Processing Cell Points file 3");
	IMStoBrainJCells(CellsC2, 3);
	print("Channel 3 complete.");
}

print("------------------------");
print("*** Conversion complete ***");

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

function IMStoBrainJCells(CellsFile, CNum) {
		// takes csv file of cell locations from Imaris and saves a cell file to the BrainJ subfolder
	
	// Read in CSV as string
	filestring=File.openAsString(CellsFile);
	rows=split(filestring, "\n"); 
	
	// delete top rows but leave column headers
	
	// Check for headers
	HeadersRow = 0;
	for(i=0; i<7; i++){ 
		if(matches(rows[i],".*Position X.*") == 1 ){
		HeadersRow = i;
	}
		
	}
	// Check for 0 columns, if they exist, delete every second row, and Create Table
	
	
	run("Text Window...", "name=TempPoints");
	
	if (lengthOf(rows[HeadersRow +1]) == 0 && lengthOf(rows[HeadersRow +3]) == 0) {
		print(".csv from Imaris only contains information on every second row");
		//filestringout = "";
		for(i=0+HeadersRow; i<(rows.length-HeadersRow); i++) {
			print("[TempPoints]", rows[i] + "\n");
			i++;
		} 
			
	
	} else {
	
		for(i=0+HeadersRow; i<(rows.length); i++){
			print("[TempPoints]", rows[i] + "\n");
		}
	
	
	}

	
	// save as table and reimport
	// create array for X Y and Z - import and multiply by original resolution
	
	run("Text...", "save=["+OutputDir +"/TempPoints.csv]");
	closewindow("TempPoints.csv");
	
	open(OutputDir + "/TempPoints.csv");
	Table.rename(Table.title, "Results");
	
	ChCount = nResults;
	XPos = newArray(nResults);
	YPos = newArray(nResults);
	ZPos = newArray(nResults);
	for (i = 0; i < ChCount; i++) {
		XPos[i] = ((getResult("Position X", i)/InputResArr[0])* ResampleX);
		YPos[i] = ((getResult("Position Y", i)/InputResArr[1])* ResampleY);
		ZPos[i] = ((getResult("Position Z", i)/InputResArr[2])* ResampleZ) * ZRes; //*** Had to add this to resolve issue with points
		// ZPos calc should not need to be multiplied by Zres, could be data issue, check here if issues
		
	}

	if (Flip == true) {
		for (i = 0; i < ChCount; i++) {
			XPos[i] = (Height - XPos[i])-TOPY;
		}
	}
	if (OrientationArr[0] == "DV" && OrientationArr[1] == "AP") {
		for (i = 0; i < ChCount; i++) {
			YPos[i] = (Width - YPos[i])-TOPX;
			
	}

	close("Results");
	
	title1 = "Resampled"; 
	title2 = "["+title1+"]"; 
	f=title2; 
	run("New... ", "name="+title2+" type=Table"); 
	//print(f,"\\Headings:C1\tC2\tC3"); 


	if (OrientationArr[0] == "DV" && OrientationArr[1] == "AP") {
		for (i=0; i<ChCount; i++) { 
			print(f, YPos[i]+"\t"+XPos[i]+"\t"+ZPos[i]); 
			
		}	
	} else {
		for (i=0; i<ChCount; i++) { 
			print(f, XPos[i]+"\t"+YPos[i]+"\t"+ZPos[i]); 
		}
	}

// save as table in cell analysis


saveAs("Results", CellsOut1 + "Cell_Points_Ch"+CNum+".csv");
saveAs("Results", CellsOut2 + "Cell_Points_Ch"+CNum+".csv");
close("Resampled");
DeleteFile(OutputDir +"/TempPoints.csv");


}


function DeleteFile(Filelocation){
	if (File.exists(Filelocation)) {
		a=File.delete(Filelocation);
	}
}