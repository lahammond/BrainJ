// Threshold and Measure in Atlas

// Author: 	Luke Hammond
// Cellular Imaging | Zuckerman Institute, Columbia University
// Date:	13th September, 2021

// Initialization
requires("1.53c");
run("Options...", "iterations=3 count=1 black edm=Overwrite");
run("Colors...", "foreground=white background=black selection=yellow");
run("Clear Results"); 
run("Close All");

#@ File(label="Select experiment/brain folder:", style="directory") input
//#@ File(label="Select template/annotation direcotry to be used (e.g. ABA CCF 2017):", style="directory") AtlasDir
#@ Integer(label="Channel to be analyzed:", description="") Ch
//#@ File(label="Elastix location:", value = "C:/Program Files/elastix_v5_0", style="directory") Elastixdir
#@ String(label="Provide name for output file (Saved to 5_Analysis_Output/Threshold_Measurement:", style = "text field") outputname


close("*");
setBatchMode(true);

/////////////////// Intialization and Parameters //////////////////////////////////////////////////////////////////////////////////////////////////////

input = input + "/";

ProAnRes = 10;

// Read in parameters 
if (File.exists(input + "/Experiment_Parameters.csv")) {
		ParamFile = File.openAsString(input + "/Experiment_Parameters.csv");
		ParamFileRows = split(ParamFile, "\n"); 
	} else {
		exit("Experiment Parameter file doesn't exist, please run Setup Experiment Parameters step for this folder first");
	}
	// Get Experiment Parameters

SampleType = LocateValue(ParamFileRows, "Sample Type");
FinalRes = parseFloat(LocateValue(ParamFileRows, "Final Resolution"));
RegRes = FinalRes;
AlignCh = parseInt(LocateValue(ParamFileRows, "DAPI/Autofluorescence channel"));
BGround = parseInt(LocateValue(ParamFileRows, "Background intensity"));
	ZCut = parseInt(LocateValue(ParamFileRows, "Section cut thickness"));
	AnalysisType = LocateValue(ParamFileRows, "Analysis Type");
//RegionNumbers = getResultString("Value", 12);
//SCSegRange array start = 0 end = 1


if (AlignCh == Ch) {
	FinalRes = 25;
	ProAnRes = 25;
}

if (File.exists(input)) {
	if (File.isDirectory(input)) {
		starttime = getTime();
			
		close("Results");
		//cleanupROI();
		print("\\Clear");
		print("Processing folder: "+input);
	    print("");
	    if (File.exists(input + "5_Analysis_Output/Threshold_Measurement") == 0) {
	    	File.mkdir(input + "5_Analysis_Output/Threshold_Measurement");
	    }

	    // Import raw stack
	    inputdir = input + "3_Registered_Sections/"+Ch;
		rawSections = getFileList(inputdir);
		rawSections = Array.sort( rawSections );
		Section1 = rawSections[0];
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=100 sort");
		print("   Adjusting scale so that lateral resolution = "+ProAnRes+" micron.");
		// Rescale if necessary 
	
		if (ProAnRes < FinalRes) {
			ProAnRes = FinalRes;
		}
		scaledown = FinalRes/ProAnRes;
		//scaledown = smW/outputres;
		//scaleZ = ZCut/ProAnResSection;
		scaleZ = 1;
		
		run("Scale...", "x="+scaledown+" y="+scaledown+" z="+scaleZ+" interpolation=None process create");
		run("Divide...", "value=255 stack");
		rename("ExpProjections");
		close("\\Others");
		saveAs("Tiff", input + "5_Analysis_Output/Threshold_Measurement/C"+Ch+"_"+outputname+".tif");
		close("*");
		print("Image created.");
	}
}



function collectGarbage(slices, itr){
	setBatchMode(false);
	wait(1000);
	for(i=0; i<itr; i++){
		wait(50*slices);
		run("Collect Garbage");
		call("java.lang.System.gc");
		}
	setBatchMode(true);
}

		
function OpenAsHiddenResults(table) {			
	open(table);
	Table.rename(Table.title, "Results");
	selectWindow("Results");
	selectWindow("Log");
	selectWindow("Results");
	setLocation(screenWidth, screenHeight);
}		
	        

function CreateCmdLine(location) {
	q ="\"";
	variable = location;
	variable = replace(variable, "\\", "/");
	variable = q + variable + q;
	return variable;
	
}
function CreateBatFile(Command, outputdirectory, filename) {
	run("Text Window...", "name=Batch");
	//print("[Batch]", "@echo off" + "\n");
	print("[Batch]", Command);
	// check - will this overwrite if already present?
	run("Text...", "save=["+ outputdirectory +"/"+filename+".bat]");
	selectWindow(filename+".bat");
	run("Close"); 
}

function DeleteDir(Dir){
	listDir = getFileList(Dir);
  	//for (j=0; j<listDir.length; j++)
     ///print(listDir[j]+": "+File.length(myDir+list[i])+"  "+File. dateLastModified(myDir+list[i]));
 	
 	// Delete the files and the directory
	for (j=0; j<listDir.length; j++)
		ok = File.delete(Dir+listDir[j]);
	ok = File.delete(Dir);
	//if (File.exists(Dir))
	    //print("\\Update13: Unable to delete temporary directory"+ Dir +".");
	//else
	    //print("\\Update13: Temporary directory "+ Dir +" and files successfully deleted.");
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

function TransformAnnotationDataset() {

// 1) Check if already transformed before proceeding:
	ProTstarttime = getTime();
	print("Transforming annotation dataset...");
	
	if (File.exists(input + "5_Analysis_Output/Transformed_Annotations.tif")) {
		print("     Transformed annotation dataset already created.");
	} else {

		if (File.exists(input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.0.txt") == 0 ) {
   			exit("Atlas registration files cannot be found - ensure atlas registration step has been performed.");
   		}
		
		//Create Annotation Transformation file 0
		filestring=File.openAsString(input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.0.txt"); 
		rows=split(filestring, "\n"); 
		
		//Search for required rows		
		for(i=0; i<rows.length; i++){ 
			if(matches(rows[i],".*FinalBSplineInterpolationOrder.*") == 1) {
				BSplineRow=i;
			}	
			if(matches(rows[i],".*ResultImagePixelType.*") == 1) {
				ResultPixelTypeRow=i;
			}
		}

		//Create new array lines
		newBSpline = "(FinalBSplineInterpolationOrder 0)";		
		newPixelType = "(ResultImagePixelType \"float\")";

		//Update Array lines
		rows[BSplineRow] = newBSpline;
		rows[ResultPixelTypeRow] = newPixelType;			
	
		run("Text Window...", "name=NewTransParameters");
		for(i=0; i<rows.length; i++){ 
			print("[NewTransParameters]", rows[i] + "\n");
		}
	
		selectWindow("NewTransParameters");
		run("Text...", "save=["+ input + "5_Analysis_Output/Transform_Parameters/Annotation_TransformParameters.0.txt]");		
		close("Annotation_TransformParameters.0.txt");

		
	// Create Annotation transform file 1

		filestring=File.openAsString(input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.1.txt"); 
		rows=split(filestring, "\n"); 
	
		//Search for required rows	
		for(i=0; i<rows.length; i++){ 
			if(matches(rows[i],".*InitialTransformParametersFileName.*") == 1 ){
				ParamRow=i;
			}
			if(matches(rows[i],".*FinalBSplineInterpolationOrder.*") == 1) {
				BSplineRow=i;
			}
			if(matches(rows[i],".*ResultImagePixelType.*") == 1) {
				ResultPixelTypeRow=i;
			}
		}
	
		//Create new array lines
		newParam ="(InitialTransformParametersFileName "+ q + input + "5_Analysis_Output/Transform_Parameters/Annotation_TransformParameters.0.txt"+q+")";
		newBSpline = "(FinalBSplineInterpolationOrder 0)";
		newPixelType = "(ResultImagePixelType \"float\")";
			
		//Update Array lines
		rows[ParamRow] = newParam;
		rows[BSplineRow] = newBSpline;
		rows[ResultPixelTypeRow] = newPixelType;						
	
		run("Text Window...", "name=NewTransParameters");
		for(i=0; i<rows.length; i++){ 
			print("[NewTransParameters]", rows[i] + "\n");
		}
	
		selectWindow("NewTransParameters");
		run("Text...", "save=["+ input + "5_Analysis_Output/Transform_Parameters/Annotation_TransformParameters.1.txt]");		
		close("Annotation_TransformParameters.1.txt");

		// CREATE RAW DATA TRANSFORMATION PARAMETERS
		
		print("     Annotation transform parameters created.");
	
	
	// Read in the number of slices in the raw data - to rescale the annotated data.
		//Count number of registered slices
		RegSectionsCount = getFileList(input+ "/3_Registered_Sections/1/");	
		RegSectionsCount = RegSectionsCount.length;		
	
		// Transform annotation file
		File.mkdir(input + "5_Analysis_Output/Temp/AnnOut");

		AnnotationImage = CreateCmdLine(AtlasDir + "Annotation.tif");
		AnnTransParam = CreateCmdLine(input + "5_Analysis_Output/Transform_Parameters/Annotation_TransformParameters.1.txt");
		AnnotationImageOut = CreateCmdLine(input + "5_Analysis_Output/Temp/AnnOut/");
			
		TransformCmd = Transformix +" -in "+AnnotationImage+" -tp "+AnnTransParam+" -out "+AnnotationImageOut;

		

		CreateBatFile (TransformCmd, input, "TransformixRun");
		runCmd = CreateCmdLine(input + "TransformixRun.bat");
		exec(runCmd);

		run("MHD/MHA...", "open=["+ input + "5_Analysis_Output/Temp/AnnOut/result.mhd]");
		run("Size...", "depth="+RegSectionsCount+" interpolation=None");
		saveAs("Tiff", input + "5_Analysis_Output/Transformed_Annotations.tif");
		close("*");			
		DeleteDir(input + "5_Analysis_Output/Temp/AnnOut/");
		File.makeDirectory(input + "5_Analysis_Output/Temp/AnnOut/");


		open(AtlasDir + "Annotation.tif");
		run("8-bit");
		run("Select All");
		setBackgroundColor(0, 0, 0);
		run("Clear", "stack");
		run("Select None");
		//run("Reslice [/]...", "output=1.000 start=Left rotate avoid");
		//close("Annotation");
		//selectWindow("Reslice of Annotation");
		makeRectangle(0, 0, parseInt(AtlasSizeX/2), AtlasSizeY);
		setForegroundColor(255, 255, 255);
		run("Fill", "stack");
		//run("Reslice [/]...", "output=1.000 start=Left rotate avoid");
		saveAs("Tiff", input + "5_Analysis_Output/Temp/AnnOut/Hemisphere_Annotation.tif");
		close("*");
				
		HemisphereImage = CreateCmdLine(input + "5_Analysis_Output/Temp/AnnOut/Hemisphere_Annotation.tif");
			
		
		TransformCmd = Transformix +" -in "+HemisphereImage+" -tp "+AnnTransParam+" -out "+AnnotationImageOut;

		CreateBatFile (TransformCmd, input, "TransformixRun");
		runCmd = CreateCmdLine(input + "TransformixRun.bat");
		exec(runCmd);
		
		run("MHD/MHA...", "open=["+ input + "5_Analysis_Output/Temp/AnnOut/result.mhd]");
		run("8-bit");
		run("Size...", "depth="+RegSectionsCount+" interpolation=None");
		saveAs("Tiff", input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif");
		close("*");	


		DeleteFile(input+"TransformixRun.bat");
		DeleteDir(input + "5_Analysis_Output/Temp/AnnOut/");
		print("   Annotation transformation complete.");
	}
		
	ProTendtime = getTime();
	dif = (ProTendtime-ProTstarttime)/1000;
	print("Transformation processing time: ", (dif/60), " minutes.");

}

function DeleteFile(Filelocation){
	if (File.exists(Filelocation)) {
		a=File.delete(Filelocation);
	}
}


function CreateHemisphereMask() {


	
}