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
#@ File(style="file", label = "Image to be analyzed:") inputimage
#@ File(label="Select template/annotation direcotry to be used (e.g. ABA CCF 2017):", style="directory") AtlasDir
#@ File(label="Elastix location:", value = "C:/Program Files/elastix_v5_0", style="directory") Elastixdir



setBatchMode(true);

/////////////////// Intialization and Parameters //////////////////////////////////////////////////////////////////////////////////////////////////////
starttime = getTime();

imagetitle = split(inputimage, "\\");
imagetitle = imagetitle[lengthOf(imagetitle)-1];
imagetitle =substring(imagetitle, 0, lengthOf(imagetitle)-4);


AtlasDir = AtlasDir + "/";
input = input + "/";
Elastixdir = Elastixdir + "/";
Transformix = CreateCmdLine(Elastixdir + "transformix.exe");
q ="\"";

if (File.exists(AtlasDir + "Annotation_Info.csv")) {
	ParamFile = File.openAsString(AtlasDir + "Annotation_Info.csv");
	ParamFileRows = split(ParamFile, "\n"); 
       			
	} else {
		exit("Annotation Information file doesn't exist, please ensure you are using a provided template/annotation dataset. \nOtherwise create an Annotation Info.csv file for your annotation/template dataset.");
	}

	// Get Annotation info
	AtlasName = LocateValue(ParamFileRows, "Name");
	AtlasType = LocateValue(ParamFileRows, "Type");
	if (AtlasType == 0) {
		AtlasType = "Mouse brain";
	}
	AtlasResXY = parseInt(LocateValue(ParamFileRows, "Template_XY_Resolution"));
	AtlasResZ = parseInt(LocateValue(ParamFileRows, "Template_Z_Resolution"));
	Template_Orientation = LocateValue(ParamFileRows, "Template_Orientation");
	AtlasSizeX = parseInt(LocateValue(ParamFileRows, "Dim_X"));
	AtlasSizeY = parseInt(LocateValue(ParamFileRows, "Dim_Y"));
	AtlasSizeZ = parseInt(LocateValue(ParamFileRows, "Dim_Z"));
	Masks_Exist = LocateValue(ParamFileRows, "Masks");
	Modified_IDs = LocateValue(ParamFileRows, "ModifiedIDs");

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


if (File.exists(input + "/Analysis_Settings.csv")) {
	ParamFile = File.openAsString(input + "/Analysis_Settings.csv");
	ParamFileRows = split(ParamFile, "\n"); 
	
	} else {
		exit("Analysis Settings file doesn't exist, please run Setup Experiment Parameters step for this folder first");
	}
		
	//ProAnRes = parseInt(LocateValue(ParamFileRows, "Projection ResolutionXY"));



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
		open(inputimage);
		getPixelSize(unit, pixelWidth, pixelHeight);
		ProAnRes = pixelWidth;
		setBatchMode("show");
		setSlice(nSlices/2);
		run("Threshold...");
		setAutoThreshold("Default dark stack");
		waitForUser("Adjust the threshold to match the object/s you wish to measure using atlas annotations.\nThen click OK.");
		run("Convert to Mask", "method=Default background=Dark black");
		setBatchMode("hide");
		run("Divide...", "value=255 stack");
		rename("Mask");
		getDimensions(IMwidth, IMheight, channels, IMslices, frames);
		
		if (File.exists(input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif") == 0) {
			CreateHemisphereMask();
		}
		MeasureMaskinAnnotationsAdvanced("Mask", AtlasDir);
		endtime = getTime();
		dif = (endtime-starttime)/1000;
		print("Total processing time: ", (dif/60), "minutes.");
	}
}


function CreateHemisphereMask() {

	File.mkdir(input + "5_Analysis_Output/Temp");
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
	saveAs("Tiff", input + "5_Analysis_Output/Temp/Hemisphere_Annotation.tif");
	close();
			
	HemisphereImage = CreateCmdLine(input + "5_Analysis_Output/Temp/Hemisphere_Annotation.tif");
				
	TransformAnnotationDataset();
		
		
	Transformix = CreateCmdLine(Elastixdir + "transformix.exe");
	
	AnnTransParam = CreateCmdLine(input + "5_Analysis_Output/Transform_Parameters/Annotation_TransformParameters.1.txt");
	AnnotationImageOut = CreateCmdLine(input + "5_Analysis_Output/Temp/");
	
	TransformCmd = Transformix +" -in "+HemisphereImage+" -tp "+AnnTransParam+" -out "+AnnotationImageOut;

	CreateBatFile (TransformCmd, input, "TransformixRun");
	runCmd = CreateCmdLine(input + "TransformixRun.bat");
	exec(runCmd);
	
	run("MHD/MHA...", "open=["+ input + "5_Analysis_Output/Temp/result.mhd]");
	run("8-bit");
	run("Size...", "depth="+RegSectionsCount+" interpolation=None");
	saveAs("Tiff", input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif");
	close();
	DeleteDir(input + "5_Analysis_Output/Temp/");
}




function MeasureMaskinAnnotationsAdvanced(Mask, AtlasDir) {

	open(input + "5_Analysis_Output/Transformed_Annotations.tif");
	rename("Annotations");
	run("Size...", "width="+IMwidth+" height="+IMheight+" depth="+IMslices+" interpolation=None");

	// Import Hemisphere Mask
	open(input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif");
	rename("Hemi_Annotations");
	run("Divide...", "value=255 stack");
	run("Size...", "width="+IMwidth+" height="+IMheight+" depth="+IMslices+" interpolation=None");
	
	// Open annotation table		
	OpenAsHiddenResults(AtlasDir + "Atlas_Regions.csv");
	NumIDs = (nResults);
	RegionIDs = newArray(NumIDs);
	if (Modified_IDs == "true") {
		OutputRegionIDs = newArray(NumIDs);
	}
	RegionNames = newArray(NumIDs);
	RegionAcr = newArray(NumIDs);
	ParentIDs = newArray(NumIDs);
	ParentNames = newArray(NumIDs);
	Graph_Order = newArray(NumIDs);
	Graph_Path = newArray(NumIDs);
	
	for(i=0; i<NumIDs; i++) {
		RegionIDs[i] = getResult("id", i);
		if (Modified_IDs == "true") {
			OutputRegionIDs[i] = getResult("output_id", i);
		}
		RegionNames[i] = getResultString("name", i);
		RegionAcr[i] = getResultString("acronym", i);
		ParentIDs[i] = getResultString("parent_ID", i);
		ParentNames[i] = getResultString("parent_acronym", i);	
		Graph_Order[i] = getResultString("graph_order", i);	
		Graph_Path[i] = getResultString("graph_ID_path", i);	
	}

	// Then measure volume of regions in cropped annotated brain - check if it's already been measured

	if (File.exists(input+"/5_Analysis_Output/Annotated_Volumes_XY_"+ProAnRes+"_Z_"+ZCut+"micron.csv")) {
		print("Annotated volumes already measured, proceeding to measure projection volumes");
		open(input+"/5_Analysis_Output/Annotated_Volumes_XY_"+ProAnRes+"_Z_"+ZCut+"micron.csv");
		Table.rename(Table.title, "Results");
		VolumesLeft = newArray(NumIDs);
		VolumesRight = newArray(NumIDs);
		for(i=0; i<NumIDs; i++) {
			VolumesLeft[i] = getResult("Volume_Left", i);
			VolumesRight[i] = getResult("Volume_Right", i);
		}
		close("Results");		
	} else {
		print("   Measuring volume of annotated regions...");
		VolumesLeft = newArray(NumIDs);
		VolumesRight = newArray(NumIDs);
				
		for (j=0; j<NumIDs; j++) {
			selectWindow("Annotations");
			volume=0;
			run("Duplicate...", "title=Annotations-Sub duplicate");
			selectWindow("Annotations-Sub");
			setThreshold(RegionIDs[j], RegionIDs[j]);
			run("Convert to Mask", "method=Default background=Dark black");
			run("Divide...", "value=255 stack");
			run("Clear Results"); 
			
			//Measure for Right side
			imageCalculator("Multiply create stack", "Annotations-Sub","Hemi_Annotations");
			selectWindow("Result of Annotations-Sub");	
			IMslices = nSlices;

			for (slice=1; slice<=IMslices; slice++) { 
			    setSlice(slice); 
				getRawStatistics(n, mean, min, max, std, hist); 
				volume = volume + (hist[1]);    					
			}
			VolumesRight[j] = volume;
			volume = 0;
			close("Result of Annotations-Sub");
			
			//Measure for Left side
			imageCalculator("Subtract create stack", "Annotations-Sub","Hemi_Annotations");
			selectWindow("Result of Annotations-Sub");		
			for (slice=1; slice<=IMslices; slice++) { 
			    setSlice(slice); 
				getRawStatistics(n, mean, min, max, std, hist); 
				volume = volume + (hist[1]);    			
				}
			VolumesLeft[j] = volume;
			volume = 0;
			close("Result of Annotations-Sub");
			close("Annotations-Sub");					
			}

		title1 = "Annotated_Volumes"; 
		title2 = "["+title1+"]"; 
		f=title2; 
		run("New... ", "name="+title2+" type=Table"); 
		print(f,"\\Headings:Volume_Right\tVolume_Left\tID"); 
		 
		// print each line into table 
			if (Modified_IDs == "true") {
				for(i=0; i<RegionIDs.length; i++){ 
					print(f,VolumesRight[i]+"\t"+VolumesLeft[i]+"\t"+OutputRegionIDs[i]);
				} 
			} else {
				for(i=0; i<RegionIDs.length; i++){ 
					print(f,VolumesRight[i]+"\t"+VolumesLeft[i]+"\t"+RegionIDs[i]);
				} 
			}
		selectWindow(title1);
		//Find way of renaming table to results so that it can be edited as results. For NOW just save and reopen
		//IJ.renameResults(title1,"Results");
		run("Text...", "save=["+ input+"/5_Analysis_Output/Annotated_Volumes_XY_"+ProAnRes+"_Z_"+ZCut+"micron.csv]");
		close(title1);
		}		
		print("   Measurements complete.");

		print("   Measuring thresholded region in annotations...");
		
		// multiply atlas with annotations
		selectWindow(Mask);
		run("32-bit");
		selectWindow("Annotations");
		imageCalculator("Multiply create stack", Mask,"Annotations");
		selectWindow("Result of Mask");
		close("\\Others");		
		saveAs("Tiff", input + "5_Analysis_Output/Threshold_Measurement/"+imagetitle+"_Annotated_Threshold.tif");
		rename("Result of Mask");
		// Import Hemisphere Mask
		open(input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif");
		rename("Hemi_Annotations");
		run("Divide...", "value=255 stack");
		run("Size...", "width="+IMwidth+" height="+IMheight+" depth="+IMslices+" interpolation=None");	
		rename("Hemi_Annotations");
	

		//ExpVolumes = newArray(RegionIDs.length);
		ExpVolumesRight = newArray(NumIDs);
		ExpVolumesLeft = newArray(NumIDs);
		IMslices = nSlices;
					
		for (j=0; j<NumIDs; j++) {
			
			selectWindow("Result of Mask");
			volume=0;
			run("Duplicate...", "title=Annotations-Sub duplicate");
			
			selectWindow("Annotations-Sub");
			setThreshold(RegionIDs[j], RegionIDs[j]);
			run("Convert to Mask", "method=Default background=Dark black");
			run("Clear Results"); 

			//Measure for Right side
			imageCalculator("Multiply create stack", "Annotations-Sub","Hemi_Annotations");
			selectWindow("Result of Annotations-Sub");		
			for (slice=1; slice<=IMslices; slice++) { 
			    setSlice(slice); 
				getRawStatistics(n, mean, min, max, std, hist); 
				volume = volume + (hist[255]);    					
			}
			ExpVolumesRight[j] = volume;
			volume = 0;
			close("Result of Annotations-Sub");
			
			//Measure for Left side
			imageCalculator("Subtract create stack", "Annotations-Sub","Hemi_Annotations");
			selectWindow("Result of Annotations-Sub");		
			for (slice=1; slice<=IMslices; slice++) { 
			    setSlice(slice); 
				getRawStatistics(n, mean, min, max, std, hist); 
				volume = volume + (hist[255]);    			
				}
			ExpVolumesLeft[j] = volume;
			volume = 0;
			close("Result of Annotations-Sub");
			close("Annotations-Sub");					
			}

	
		//calculate total projection volume for relative density calculation
		Array.getStatistics(ExpVolumesLeft,_,_,ExpVolumesMEANLeft,_); 
		Array.getStatistics(ExpVolumesRight,_,_,ExpVolumesMEANRight,_); 
		TotalProjectionVolume = (ExpVolumesMEANLeft*ExpVolumesLeft.length)+(ExpVolumesMEANRight*ExpVolumesRight.length);

		//put region counts into table.. do we need any other columns?
		title1 = "Annotated_Volumes"; 
		title2 = "["+title1+"]"; 
		f=title2; 
		run("New... ", "name="+title2+" type=Table"); 
		print(f,"\\Headings:Region_Volume_Right\tRegion_Volume_Left\tProjection_Volume_Right\tProjection_Volume_Left\tProjection_Density_Right\tProjection_Density_Left\tRelative_Density_Right\tRelative_Density_Left\tID\tAcronym\tName\tGraph_Order\tParent_ID\tParent_Acronym\tGraph_ID_Path"); 
		
		//print(f,"\\Headings:Count\tRegion_ID\tName\tAcronym\tParent_Acronym"); 
		// print each line into table 
		
		OpenAsHiddenResults(AtlasDir + "Atlas_Regions.csv");
	
		if (Modified_IDs == "true") {
			RegionIDs = OutputRegionIDs;
		}
	
		for(i=0; i<RegionNames.length; i++){ 
			
			DensityRight = (ExpVolumesRight[i]/VolumesRight[i])*100;
			DensityLeft = (ExpVolumesLeft[i]/VolumesLeft[i])*100;
			RelativeDensityRight = (ExpVolumesRight[i]/TotalProjectionVolume)*100;
			RelativeDensityLeft = (ExpVolumesLeft[i]/TotalProjectionVolume)*100;
			if (isNaN(DensityRight) == 1) {
				DensityRight = 0;
			}
			if (isNaN(DensityLeft) == 1) {
				DensityLeft = 0;
			}
	
			print(f,VolumesRight[i]+"\t"+VolumesLeft[i]+"\t"+ExpVolumesRight[i]+"\t"+ExpVolumesLeft[i]+"\t"+DensityRight+"\t"+DensityLeft+"\t"+RelativeDensityRight+"\t"+RelativeDensityLeft+"\t"+RegionIDs[i]+","+RegionAcr[i]+",\""+RegionNames[i]+"\","+Graph_Order[i]+","+ParentIDs[i]+",\""+ParentNames[i]+"\",\""+Graph_Path[i]+"\"");
		} 
		close("Results");
		selectWindow(title1);
		//Find way of renaming table to results so that it can be edited as results. For NOW just save and reopen
		//IJ.renameResults(title1,"Results");
		run("Text...", "save=["+ input+"/5_Analysis_Output/Threshold_Measurement/"+ imagetitle +"_Measured_Threshold_Volume_and_Density_"+ProAnRes+"_Z_"+ZCut+"micron.csv]");
		close(title1);
		collectGarbage(10, 4);	
		close("*");
		print("Measurements complete.");
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