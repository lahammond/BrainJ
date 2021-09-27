// 3D Registration Cell Detection and Atlas Registration combined

// Author: 	Luke Hammond
// Cellular Imaging | Zuckerman Institute, Columbia University
// Date:	1st November 2017


// This pipeline makes use of the following plugins: 
//		StackReg
// 		MulitstackReg
//		Attentuation Correction (can run without)

// 2/7/2017: V2 Updated work with new TIF exports from Reformat Series 
// 2/7/2017: V3 Updated to use modified Multistackreg, for downscale of 10 and cropping to save time
// 2/8/2017: v4 updated to export stacks to improve memory handling for registering large datasets
// 2/12/2017 v5 Additional memory management to ensure only 1 channel in RAM
// 4/24/2018:V6 updated to allow batch processing
// 5/06/2018 -- Merging of all tools no longer requies modified multistackreg

// Initialization
requires("1.53c");
run("Options...", "iterations=3 count=1 black edm=Overwrite");
run("Colors...", "foreground=white background=black selection=yellow");
run("Clear Results"); 
run("Close All");

BrainJVer ="BrainJ 1.0.2";
ReleaseDate= "September 24, 2021";


#@ File[] listOfPaths(label="Select experiment/brain folders:", style="both")
#@ File(label="Select template/annotation direcotry to be used (e.g. ABA CCF 2017):", style="directory") AtlasDir

#@ boolean(label="1. Perform section registration?", description="Required for further analysis. Turn off if already performed.") SectionRegON
#@ boolean(label="2. Perform atlas registration?", description="Required for further analysis.") AtlasAnalysisON
#@ boolean(label="3. Perform cell detection and analysis?", description="Required for further analysis. Turn off if already performed.") CellAnalysisON
#@ boolean(label="    Genearate cell analysis images and heatmaps?", description="") CreateCellAnalysisVisON
#@ boolean(label="4. Perform mesoscale mapping projection analysis?", description="Required for projection analysis. Turn off if already performed.") ProjectionTransformationON
#@ boolean(label="    Genearate mesoscale mapping visualization images and heatmaps?") CreateProjectionDensityVisON
#@ boolean(label="5. Measure mean intensities of annotated regions?", description="") IntensityMeasureInABAON
#@ boolean(label="    Genearate intensity based atlas images?") CreateIntensityMapsON
#@ boolean(label="6. Transform orignal channel images into template space?", description="") RawChannelTransformON
#@ boolean(label="7. Extract specific regions at full resolution (requires min 128 RAM)", description="") FullResExtractON
#@ string(label="    Provide annotation IDs for extraction (e.g. 4,10)", style="text field", value = " ", description="Provide annotation id/intensity to be extracted at full resolution.") ExRegionsStr


#@ String (visibility=MESSAGE, value="- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ") docms

// Output type no longer optional
//#@ String(label="Visualization output type:", choices={"Sagittal", "Coronal"}, style="listBox", description="Ensure you select the corresponding atlas files.") OutputType
OutputType = "Coronal";

// Put in option for GPU processing
//#@ boolean(label="Use GPU-acceleration (requires CLIJ)?", value = false, description="") GPU_ON

// Options for Custom Templates and Registration - Take these out and only active for ADVANCED MODE (e.g. 5b)
//#@ boolean(label="Use a custom template for registration?", value = false, description="Provide custom template for specific projects.") SpecificTemplateON
//#@ File(label="Custom template file:", value = "C:/select folder", style="file", value = " ", description="Only required if performing specialized registration using a modified template.") AtlasTemplateLocation
//#@ boolean(label="Mask tissue to assist alignment?", value = false, description="Creates a binary mask of brain or tissue region to be aligned.") ExpBrainMaskON
//#@ boolean(label="Provide a custom mask to assist alignment?", value = false, description="Uses a provided binary mask in the atlas space to assist alignment.") AtlasMaskON
//#@ File(label="Custom template mask file:", value = "C:/select folder", style="file", value = " ", description="Only required if performing an alignment with a custom template.") AtlasMaskLocation
SpecificTemplateON = false;
AtlasTemplateLocation = " ";
ExpBrainMaskON = false;
AtlasMaskON = false;
AtlasMaskLocation = " ";

GPU_ON = false;


if (GPU_ON == true) {
	List.setCommands;
	if (List.get("Histogram on GPU") != "") {
		// Init GPU
		run("CLIJ Macro Extensions", "cl_device=");
		Ext.CLIJ_clear();
	      	        
	} else {
		print("***CLIJ2 not installed. Please visit https://clij.github.io/ for installation instructions. Processing will run on CPU.");
		GPU_ON = false;
	}
	
}

// OPEN ROI MANAGER - bug in imagej if roi manager not open list can be empty? started april 2021
run("ROI Manager...");

setBatchMode(true);

//Visualization options
if (CreateProjectionDensityVisON == 1) {
	CreateABADensityHeatmapON = true;
	CreateColorDensityImagesON = true;
} else {
	CreateABADensityHeatmapON = false;
	CreateColorDensityImagesON = false;
}
		

/////////////////// Intialization and Parameters //////////////////////////////////////////////////////////////////////////////////////////////////////
for (FolderNum=0; FolderNum<listOfPaths.length; FolderNum++) {
	inputdir=listOfPaths[FolderNum];
    if (File.exists(inputdir)) {
        if (File.isDirectory(inputdir)) {
			starttime = getTime();
			input = inputdir + "/";
			close("Results");
			cleanupROI();
			print("\\Clear");
			print("- - - " +BrainJVer+ " - - -");
			print("Version release date: " +ReleaseDate);
			print("  ");
			print("Processing folder "+(FolderNum+1)+" of "+listOfPaths.length+" folders selected for processing." );
	        print("  Folder:" + inputdir + " ");
	        print("");
	        
			// Read in parameters 
			if (File.exists(inputdir + "/Experiment_Parameters.csv")) {
	       		ParamFile = File.openAsString(inputdir + "/Experiment_Parameters.csv");
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
			SCSegRange = split(Locate2Values(ParamFileRows, "SC Segment Range"), ",");
											
			if (File.exists(inputdir + "/Analysis_Settings.csv")) {
       			ParamFile = File.openAsString(inputdir + "/Analysis_Settings.csv");
	   			ParamFileRows = split(ParamFile, "\n"); 
       			
       		} else {
       			exit("Analysis Settings file doesn't exist, please run Setup Experiment Parameters step for this folder first");
	   		}

			// Get Analysis Settings 

			StartSection = parseInt(LocateValue(ParamFileRows, "Reference section"));
			
			BGSZ = parseInt(LocateValue(ParamFileRows, "Cell Analysis BG Subtraction"));
			USSZ = parseInt(LocateValue(ParamFileRows, "Cell Analysis US Mask"));
			USMW = parseInt(LocateValue(ParamFileRows, "Cell Analysis US Mask Weight"));
			
			CellDetMethod = LocateValue(ParamFileRows, "Cell Detection Type");
			CellCh = parseInt(LocateValue(ParamFileRows, "Cell Analysis 1"));
			MaximaInt1 = parseInt(LocateValue(ParamFileRows, "Maxima Int 1"));
			size1 = parseInt(LocateValue(ParamFileRows, "Cell Analysis Cell SizeC1"));
			CellCh2 = parseInt(LocateValue(ParamFileRows, "Cell Analysis 2"));
			MaximaInt2 = parseInt(LocateValue(ParamFileRows, "Maxima Int 2"));
			size2 = parseInt(LocateValue(ParamFileRows, "Cell Analysis Cell SizeC2"));
			CellCh3 = parseInt(LocateValue(ParamFileRows, "Cell Analysis 3"));
			MaximaInt3 = parseInt(LocateValue(ParamFileRows, "Maxima Int 3"));
			size3 = parseInt(LocateValue(ParamFileRows, "Cell Analysis Cell SizeC3"));

			CellChans = newArray(CellCh,CellCh2,CellCh3);
			CellSizes = newArray(size1,size2,size3);
			CellMaxInts = newArray(MaximaInt1,MaximaInt2,MaximaInt3);

			ProjDetMethod = LocateValue(ParamFileRows, "Projection Detection Type");
			ProCh = parseInt(LocateValue(ParamFileRows, "Projection Analysis 1"));
			ProjectionMinInt1 = parseInt(LocateValue(ParamFileRows, "Projection Min Intensity 1"));
			ProCh2 = parseInt(LocateValue(ParamFileRows, "Projection Analysis 2"));
			ProjectionMinInt2 = parseInt(LocateValue(ParamFileRows, "Projection Min Intensity 2"));
			ProCh3 = parseInt(LocateValue(ParamFileRows, "Projection Analysis 3"));
			ProjectionMinInt3 = parseInt(LocateValue(ParamFileRows, "Projection Min Intensity 3"));

			ProChans = newArray(ProCh,ProCh2,ProCh3);
			ProMinInts = newArray(ProjectionMinInt1,ProjectionMinInt2,ProjectionMinInt3);

			ProAnRes = parseInt(LocateValue(ParamFileRows, "Projection ResolutionXY"));
			ProBGSub = parseInt(LocateValue(ParamFileRows, "Projection Analysis BG Subtraction"));
			ProAnResSection = parseInt(LocateValue(ParamFileRows, "Projection Resolution Zsection"));

			
			FullResDAPI = LocateValue(ParamFileRows, "Full resolution DAPI");

			ilastikdir = LocateValue(ParamFileRows, "Ilastik");
			ilastik = ilastikdir + "/run-ilastik.bat";

	//Testing ilastik Masking mode - leave false until Masks work
			ilastikmaskON = false;
			ilastikmaskthresh = 20;

			Elastixdir = LocateValue(ParamFileRows, "Elastix");
			Elastixdir = Elastixdir + "/";

			IntVal = parseInt(LocateValue(ParamFileRows, "Intensity Validation"));
			SecondPass = parseInt(LocateValue(ParamFileRows, "Perform Second Pass Reg"));

			Trim = parseInt(LocateValue(ParamFileRows, "Trim"));

			//Version checker to avoid issues with older parameter files
			BrainJV = parseInt(LocateValue(ParamFileRows, "BrainJ Version"));
			
			if (BrainJV == 0) {
				exit("Analysis settings created using an earlier version of BrainJ.\n \nPlease re-run step 4: Set Analysis Settings, for this brain.");
			}

	// Read in Template/Annotation Information File
			AtlasDir = AtlasDir + "/";
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

	//Directory Shortcuts
			RegDir = input + "3_Registered_Sections/";
			CellPointsDir = input + "4_Processed_Sections/Detected_Cells/";
			CellCountOut = input + "4_Processed_Sections/Detected_Cells/";
			CellIntensityOut = input + "4_Processed_Sections/Measured_Intensities/";
			ResampledCellPointsDir = input + "4_Processed_Sections/Resampled_Cells/";

			TransformedProjectionDataOut = input + "5_Analysis_Output/Projections_Transformed_To_Atlas_Space/";
			TransformedRawDataOut = input + "5_Analysis_Output/Raw_Data_Transformed_To_Atlas_Space/";
			q ="\"";


	//Additional Parameters	
			AlignParamCheck = 0;
			CellPlotCheck = 0;
			VisRegCheck = 0;
			random("seed", 1);
        
/////////////////// STEP 1: SECTION REGISTRATION /////////////////////////////////////////////////////////////

if (SectionRegON == true) {
		print("Performing section registration...");
	print("  Channel selected for alignment: "+ AlignCh +". Alignment channel background: "+BGround+".");
	//print("Final resolution: "+ FinalRes +"um/px. Channel selected for alignment: "+ AlignCh +". Alignment channel background: "+BGround+".");
	print("  Section cut thickness: "+ ZCut + ". Start Section for stack registration: "+ StartSection +".");
	
	// Since brain already rescaled
	//FinalRes = 0;	
	CropOn = true;
	
	//DeleteWorkingFiles = false;
	// Find out how many channels:
	ChNum = CountSubFolders(input + "1_Reformatted_Sections/");
	channels = getFileList(input + "1_Reformatted_Sections/");
	ChArray = NumberedArray(ChNum);
	
	// check if already run, otherwise create output directory
	regchannels = newArray(0);

	if (File.exists(input + "3_Registered_Sections")) {
			regchannels = getFileList(RegDir);
			if (regchannels.length >= ChNum) {
				//Note this is counting all files currently not just folders - should be folders only			
				print("Section registration already performed. Delete 3_Registered_Sections folder if you wish to rerun.");
			} 
	} 
	if (File.exists(input + "3_Registered_Sections") == 0 || (File.exists(input + "3_Registered_Sections") && regchannels.length < channels.length )) {
		
			File.mkdir(input + "3_Registered_Sections");

	/////////////// Registration ////////

	RegisterSections();
	
	// Create Cell Count folder if Manual Cell Counting Used
	if (CellDetMethod == "Manual Cell Count"){
		File.mkdir(input + "4_Processed_Sections");
		File.mkdir(input + "4_Processed_Sections/Detected_Cells");
	}
	
	//finish
	print("Translation of all full resolution channels complete.");
	finalregtime = getTime();
	dif1 = (finalregtime-starttime)/1000;
	print("     Section registration processing time = "+ (dif1/60) +" minutes.");
	print("  ");
	
}
print("---------------------------------------------------------------------------------------------------------------------");
}

/////////////////// STEP 2: ATLAS REGISTRATION ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

CheckAnnotationFile();


if (AtlasAnalysisON == true ||  ProjectionTransformationON == true || CellAnalysisON ==true || CreateCellAnalysisVisON ==true || CreateColorDensityImagesON == true || RawChannelTransformON == true || IntensityMeasureInABAON == true) {
	
	print("Performing 3D atlas registration and preparation for analysis...");
	print("  Section cut thickness: "+ ZCut + ". Atlas type: "+ AtlasType +". Atlas name: "+ AtlasName +".");
	//print("Resolution used for cell analysis: "+ FinalRes +"um/px. Section cut thickness: "+ ZCut + ". Atlas type: "+ AtlasName +".");
	print("  Channels used for detection: "+ CellCh + " " + CellCh2 + " " + CellCh3 + ". Channels used for density analysis: "+ ProCh + " " + ProCh2 + " " + ProCh3 + ".");
	print("  Method used for cell detection: "+ CellDetMethod);
	print("  Method used for projection analysis: "+ ProjDetMethod);

	print("  Elastix directory: "+ Elastixdir +".");
	print("  Atlas directory: "+ AtlasDir +".");
	
	//Get Resampling Factors (ResXYZ start / ResXYZ final) Atlas is 25x25x25 so x/25

	ResampleX = FinalRes/AtlasResXY;
	print("  Input resolution: "+FinalRes+". Atlas resolution:" +AtlasResXY+". Resample factor: " + ResampleX +".");
	print("");
	ResampleY = FinalRes/AtlasResXY;
	ResampleZ = ZCut/AtlasResZ;
	
	//Get Spacing of new dataset
	FinalSpacingX = 1;
	FinalSpacingY = 1;
	FinalSpacingZ = 1;
	
	//application prep
	Elastix = CreateCmdLine(Elastixdir + "elastix.exe");
	Transformix = CreateCmdLine(Elastixdir + "transformix.exe");
	
	//Make Directories
	File.mkdir(input + "4_Processed_Sections");
	File.mkdir(input + "4_Processed_Sections/Resampled_Cells");
	File.mkdir(input + "5_Analysis_Output");
	File.mkdir(input + "5_Analysis_Output/Temp");
	File.mkdir(input + "5_Analysis_Output/Temp/Template_aligned");
	File.mkdir(input + "5_Analysis_Output/Transform_Parameters");
	File.mkdir(input + "5_Analysis_Output/Transform_Parameters/OriginPoints");
	File.mkdir(input + "5_Analysis_Output/Temp/InvOut");
	
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (CellChans[Ch_i] > 0) {
			File.mkdir(input + "5_Analysis_Output/Temp/Ch"+CellChans[Ch_i]+"Points");
		}	
		if (ProChans[Ch_i] > 0) {
			File.mkdir(input + "5_Analysis_Output/Temp/Transformed_C"+ProChans[Ch_i]+"_Binary_Out");
		}	
	}
	


// Commandline Directories
	
	if (SpecificTemplateON == true ) {
		Template = CreateCmdLine(AtlasTemplateLocation);
	}

	if (SpecificTemplateON == true || AtlasMaskON == true ) {
		TemplateMask = CreateCmdLine(AtlasMaskLocation);
	}	

	AlignOut = CreateCmdLine(input + "5_Analysis_Output/Temp/Template_aligned/");
	Template = CreateCmdLine(AtlasDir + "Template.tif");
	
	ExpBrain = CreateCmdLine(RegDir + "DAPI_25.tif");
	ExpBrainMask = CreateCmdLine(RegDir + "DAPI_25_Mask.tif");
	AnnotationImage = CreateCmdLine(AtlasDir + "Annotation.tif");
	AnnotationImageOut = CreateCmdLine(input + "5_Analysis_Output/Temp/");
	
	Affine = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Param_Affine.txt");
	BSpline = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Param_BSpline.txt");
	BSplineLenient = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Param_BSpline_L.txt");
	BSplineUltraLenient = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Param_BSpline_UL.txt");
	InvBSpline = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Param_BSpline_Inv.txt");

	if (AnalysisType == "Isolated Region/s") {
		Affine = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Region_Param_Affine.txt");
		BSpline = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Region_Param_BSpline.txt");
		BSplineLenient = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Region_Param_BSpline_L.txt");
		BSplineUltraLenient = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Region_Param_BSpline_UL.txt");
		InvBSpline = CreateCmdLine(AtlasDir + "/Registration_Parameters/MB49_Region_Param_BSpline_Inv.txt");
	} 
	
	TransP = CreateCmdLine(input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.1.txt");
	TransPMod = CreateCmdLine(input + "5_Analysis_Output/Temp/Template_aligned/ModifiedTransformParameters.1.txt");
	InvTransPMod = CreateCmdLine(input + "5_Analysis_Output/Transform_Parameters/ProjectionTransformParameters.txt");
	OriginPoints = CreateCmdLine(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/OriginPoints.txt");
	
	AlResult = CreateCmdLine(input + "5_Analysis_Output/Temp/Template_aligned/result.1.mhd");
	
	OriginOut = CreateCmdLine(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/");
	InvOut = CreateCmdLine(input + "5_Analysis_Output/Temp/InvOut/");
	
	TransfromDAPIAF = false;
	TransfromCh1 = true;
	
}
		
if (AtlasAnalysisON == true) {			

//if Isolated Region based analysis - create masked template and mask - 
// Already created by Reformat Series or Seperate Tool
//if (AnalysisType == "Isolated Region/s") {
//	CanvasDim = CreateIsolatedTemplateRegion(RegionNumbers, AtlasDir, input + "5_Analysis_Output");	
//}
					
// Create Sagittal25 DAPI/AF image from raw data
	print("Checking for atlas scaled DAPI/Autofluorescence volume...");
	if (File.exists(RegDir + "DAPI_25.tif")) {
		print("  Registration volume of DAPI/Autofluorecence has already been created.");
	} else {			
		print("Creating 25um isotropic volume...");
		rawcoronalto3DsagittalDAPI(input+"/3_Registered_Sections/"+AlignCh, input+"/3_Registered_Sections", "DAPI_25", AtlasResXY, BGround, ZCut);
		print("  Registration volume created.");
	}
	
	CreateDAPIMask(input);
	
	// Create Origin Points
	if (File.exists(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv") == 0) {
		CreateOriginPoints();
	}

	// Modify template for Spinal Cord Analysis
	if (AtlasType == "Spinal Cord" && SCSegRange.length > 1) {
		//Get the start and end slice based on the segment information provided
		SegmentCSV = File.openAsString(AtlasDir + "Segments.csv");
		SegmentCSVRows = split(SegmentCSV, "\n"); 
		
		for(i=0; i<SegmentCSVRows.length; i++){
			// Find Start Slice
			if(matches(SegmentCSVRows[i],".*"+SCSegRange[0]+".*") == 1 ){
				Row = split(SegmentCSVRows[i], ",");
				SCStartSlice = parseInt(Row[2]);
			}
			if(matches(SegmentCSVRows[i],".*"+SCSegRange[1]+".*") == 1 ){
				Row = split(SegmentCSVRows[i], ",");
				SCEndSlice = parseInt(Row[3]);
			}
		}
		SCTotalSlices = SCEndSlice-SCStartSlice;
	
		//Modify template and create mask.
		newImage("Mask", "8-bit white", AtlasSizeX, AtlasSizeY, AtlasSizeZ);
		run("Select All");
		for(i=1; i<SCStartSlice; i++){
			setSlice(i);
			run("Clear", "slice");
		}
		for(i=SCEndSlice; i<=AtlasSizeZ; i++){
			setSlice(i);
			run("Clear", "slice");
		}
		save(input + "5_Analysis_Output/Temp/Modified_Template_Mask.tif");
		close();
		//update locations and turn on AtlasMask
		TemplateMask = CreateCmdLine(input + "5_Analysis_Output/Temp/Modified_Template_Mask.tif");
		AtlasMaskON = true;
	}



// Elastix Command Align to Template
	AAstarttime = getTime();
	print("Performing atlas alignment...");
		
	if (File.exists(input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.1.txt")) {
			print("     Alignment to atlas already performed, using existing transform parameters.");
		} else {
		
			if (AnalysisType == "Isolated Region/s") {				
				ElastixCmd = Elastix +" -f "+ExpBrain+" -fMask "+ExpBrainMask+" -m "+Template+" -mMask "+TemplateMask+" -out "+AlignOut+" -p "+Affine+" -p "+BSpline;

			} else if (AnalysisType != "Isolated Region/s" && AtlasMaskON == true && ExpBrainMaskON == false ) {
				ElastixCmd = Elastix +" -f "+ExpBrain+" -m "+Template+" -mMask "+TemplateMask+" -out "+AlignOut+" -p "+Affine+" -p "+BSpline;

			} else if (AnalysisType != "Isolated Region/s" && AtlasMaskON == true && ExpBrainMaskON == true ) {
				ElastixCmd = Elastix +" -f "+ExpBrain+" -fMask "+ExpBrainMask+" -m "+Template+" -mMask "+TemplateMask+" -out "+AlignOut+" -p "+Affine+" -p "+BSpline;
			
			} else {
				ElastixCmd = Elastix +" -f "+ExpBrain+" -m "+Template+" -out "+AlignOut+" -p "+Affine+" -p "+BSpline;

			}

			CreateBatFile (ElastixCmd, input, "Elastixrun");
			runCmd = CreateCmdLine(input + "Elastixrun.bat");
			exec(runCmd);
				
			if (File.exists(input + "5_Analysis_Output/Temp/Template_aligned/TransformParameters.1.txt")) {
				print("     Template alignment successful.");
				AlignParamCheck = 0;
			} else {
				
			print("     Initial alignment failed... attempting again with more lenient parameters.");

				if (AnalysisType == "Isolated Region/s") {
					ElastixCmd = Elastix +" -f "+ExpBrain+" -fMask "+ExpBrainMask+" -m "+Template+" -mMask "+TemplateMask+" -out "+AlignOut+" -p "+Affine+" -p "+BSplineLenient;
	
				} else if (AnalysisType != "Isolated Region/s" && AtlasMaskON == true && ExpBrainMaskON == false ) {	
					ElastixCmd = Elastix +" -f "+ExpBrain+" -m "+Template+" -mMask "+TemplateMask+" -out "+AlignOut+" -p "+Affine+" -p "+BSplineLenient;
	
				} else if (AnalysisType != "Isolated Region/s" && AtlasMaskON == true && ExpBrainMaskON == true ) {
					ElastixCmd = Elastix +" -f "+ExpBrain+" -fMask "+ExpBrainMask+" -m "+Template+" -mMask "+TemplateMask+" -out "+AlignOut+" -p "+Affine+" -p "+BSplineLenient;
				
				} else {	
					ElastixCmd = Elastix +" -f "+ExpBrain+" -m "+Template+" -out "+AlignOut+" -p "+Affine+" -p "+BSplineLenient;
	
				}
			
				CreateBatFile (ElastixCmd, input, "Elastixrun");
				runCmd = CreateCmdLine(input + "Elastixrun.bat");
				exec(runCmd);
								
				if (File.exists(input + "5_Analysis_Output/Temp/Template_aligned/TransformParameters.1.txt")) {
					print("     Template alignment successful on second attempt.");
					AlignParamCheck = 1;

				} else {
				
					print("     Second alignment attempt failed... attempting again with even more lenient parameters.");

					if (AnalysisType == "Isolated Region/s") {				
						ElastixCmd = Elastix +" -f "+ExpBrain+" -fMask "+ExpBrainMask+" -m "+Template+" -mMask "+TemplateMask+" -out "+AlignOut+" -p "+Affine+" -p "+BSplineUltraLenient;
		
					} else if (AnalysisType != "Isolated Region/s" && AtlasMaskON == true && ExpBrainMaskON == false ) {		
						ElastixCmd = Elastix +" -f "+ExpBrain+" -m "+Template+" -mMask "+TemplateMask+" -out "+AlignOut+" -p "+Affine+" -p "+BSplineUltraLenient;
		
					} else if (AnalysisType != "Isolated Region/s" && AtlasMaskON == true && ExpBrainMaskON == true ) {		
						ElastixCmd = Elastix +" -f "+ExpBrain+" -fMask "+ExpBrainMask+" -m "+Template+" -mMask "+TemplateMask+" -out "+AlignOut+" -p "+Affine+" -p "+BSplineUltraLenient;
					
					} else {		
						ElastixCmd = Elastix +" -f "+ExpBrain+" -m "+Template+" -out "+AlignOut+" -p "+Affine+" -p "+BSplineUltraLenient;
		
					}
		
					CreateBatFile (ElastixCmd, input, "Elastixrun");
					runCmd = CreateCmdLine(input + "Elastixrun.bat");
					exec(runCmd);
					
					
					if (File.exists(input + "5_Analysis_Output/Temp/Template_aligned/TransformParameters.1.txt")) {
						print("     Template alignment successful on third attempt.");
						AlignParamCheck = 2;
					} else {
						print("     Alignment failed... making final attempt with more lenient parameters.");
					
						ElastixCmd = Elastix +" -f "+ExpBrain+" -m "+Template+" -out "+AlignOut+" -p "+Affine+" -p "+BSplineUltraLenient;
					
						CreateBatFile (ElastixCmd, input, "Elastixrun");
						runCmd = CreateCmdLine(input + "Elastixrun.bat");
						exec(runCmd);
						
						
						if (File.exists(input + "5_Analysis_Output/Temp/Template_aligned/TransformParameters.1.txt")) {
							print("     Template alignment successful on final attempt.");
							AlignParamCheck = 2;
						} else {
							AlignParamCheck = 3;
							exit("Alignment to template failed. Please check quality of the dataset and correct or replace any damaged sections.") ;
						}
					}
				}							
			} 
		
		close("*");
		
		//Count number of registered slices
		RegSectionsCount = getFileList(input+ "/3_Registered_Sections/1/");	
		RegSectionsCount = RegSectionsCount.length;
		
		
		if (AlignParamCheck < 3) {
			// import transformed template
			run("MHD/MHA...", "open=["+ input + "5_Analysis_Output/Temp/Template_aligned/result.1.mhd]");
			run("Enhance Contrast...", "saturated=0.01 process_all use");
			run("Apply LUT", "stack");
			if (OutputType == "Sagittal") {
				ResliceSagittalCoronal();
			}
			rename("Result");
	
			// import experiment dataset
			open(RegDir + "DAPI_25.tif");
			run("Enhance Contrast...", "saturated=0.01 process_all use");
			run("Apply LUT", "stack");
			if (OutputType == "Sagittal") {
				ResliceSagittalCoronal();
			}
			rename("ExpBrain");
	
			//Merge and save
			run("Merge Channels...", "c1=ExpBrain c2=Result create");
			run("Size...", "depth="+RegSectionsCount+" interpolation=None");
			saveAs("Tiff", input + "5_Analysis_Output/Template_Brain_Aligned.tif");
			close("Template_Brain_Aligned.tif");
			
			//Clean up
			a = File.rename(input + "5_Analysis_Output/Temp/Template_aligned/TransformParameters.1.txt", input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.1.txt");
			a = File.copy(input + "5_Analysis_Output/Temp/Template_aligned/TransformParameters.0.txt", input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.0.txt");
			UpdateTransParamLocation0 (input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.1.txt");
			
			DeleteFile(input+"Elastixrun.bat");
			collectGarbage(10, 4);
	
			//DONT Delete Template Aligned until you have moved AFFINE transform parameters AND edited CELL_Transformparameters to contain this new location
			DeleteDir(input + "5_Analysis_Output/Temp/Template_aligned/");
			
			}
			AAendtime = getTime();
			dif = (AAendtime-AAstarttime)/1000;
			print("Atlas registration processing time: ", (dif/60), " minutes.");	
	
		//Transform Origin Point
		print("Transforming origin points to atlas...");
		if (File.exists(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv")) {
			print("  Origin points have already been transformed.");
		} else {
						
			TransformOriginCmd = Transformix +" -def "+OriginPoints+" -tp "+TransP+" -out "+OriginOut;
			
			CreateBatFile (TransformOriginCmd, input, "TransformixRun");
			runCmd = CreateCmdLine(input + "TransformixRun.bat");
			exec(runCmd);
			print("  Origin points successfully transformed to atlas space.");
			print("     ");
			//CleanUp Origin Point to .csv
			
	
			E49TransPointsToZYXcsv(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/outputpoints.txt", input + "5_Analysis_Output/Transform_Parameters/OriginPoints", "Origin_Output_Points");
			}
		print("---------------------------------------------------------------------------------------------------------------------");
	}
}


/////////////////// STEP 3: CELL and PROJECTION DETECTION ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


/////////////////// CELL ANALYSIS: Machine Learning Segmentation

if ((CellAnalysisON == true && CellDetMethod == "Machine Learning Segmentation with Ilastik") || (ProjectionTransformationON == true && ProjDetMethod == "Machine Learning Segmentation with Ilastik")) {

		ilastikstarttime = getTime();
   		
   		// Get Variables for running Reform Series

		print("Performing Ilastik based cell analysis...");
		//print("Resolution used for cell analysis: "+ FinalRes +"um/px. Channels used for detection: "+ CellCh + " " + CellCh2 + " " + CellCh3 + ".");
		print("  Channels used for detection: "+ CellCh + " " + CellCh2 + " " + CellCh3 + ".");
		//print("Cell analysis parameters. Background Subtraction: "+ BGSZ + ". Unsharp Mask Size: "+ USSZ +". Unsharp Mask Weight: "+ USMW +". Cell area (um2): "+ size +".");
		print("  Cell analysis parameters. Background Subtraction: "+ BGSZ + ". Cell area (um2): "+ size1 +", "+ size2 +", "+size3+".");
		print("  Ilastik directory: "+ ilastikdir +".");
		
		
		//Prepare Ilastik commands/ // stack by stack times out, so have to process slice by slice
		ilastik = replace(ilastik, "\\", "/");
		ilastik = q + ilastik + q;		
		inputfixed = replace(input, "\\", "/");

		ClassDir = input + "Ilastik_Projects/";
		
		File.mkdir(input + "4_Processed_Sections");
		File.mkdir(input + "4_Processed_Sections/Enhanced");
		File.mkdir(input + "4_Processed_Sections/Probability_Masks");
		File.mkdir(input + "4_Processed_Sections/Object_Detection_Validation");
		
		if (ilastikmaskON == true) {
			File.mkdir(input + "4_Processed_Sections/Ilastik_Binary_Masks");
		}


		//Process cell channels
		for (Ch_i = 0; Ch_i < 3; Ch_i++) {
			if (CellChans[Ch_i] > 0) {
				CreateProbabilityMap(CellChans[Ch_i]);
			}	
		} 
	
		// Create probability maps for any projection only channels or if not performing cell analysis
		for (Ch_i = 0; Ch_i < 3; Ch_i++) {
			if (ProChans[Ch_i] > 0) {
				CreateProbabilityMap(ProChans[Ch_i]);
			}	
		} 
		

// Detect cells - use DoG or LoG instead? add seeded watershedding based segmentation
	if (CellAnalysisON == true && CellDetMethod == "Machine Learning Segmentation with Ilastik") {
		
		File.mkdir(CellCountOut);		
		File.mkdir(CellIntensityOut);

		
		// Process Channels
		for (Ch_i = 0; Ch_i < 3; Ch_i++) {
			if (CellChans[Ch_i] > 0) {
				detectcellsfromprob(CellChans[Ch_i], CellMaxInts[Ch_i], CellSizes[Ch_i]);
			}	
		} 
		
		// Finish
		print("     Cell detection complete.");	
	}		
		
		ilastikendtime = getTime();
		dif1 = (ilastikendtime-ilastikstarttime)/1000;
		print("Ilastik processing and cell detection time = "+ (dif1/60) +" minutes.");
		print("---------------------------------------------------------------------------------------------------------------------");

}

/////////////////// CELL ANALYSIS: Find Maxima

if (CellAnalysisON == true && CellDetMethod == "Find Maxima") {
		maximastarttime = getTime();		
		print("Detecting cells by finding maxima using provided intensity...");
		//print("Resolution used for cell analysis: "+ FinalRes +"um/px. Channels used for detection: "+ CellCh + " " + CellCh2 + " " + CellCh3 + ".");
		print("  Channels used for detection: "+ CellCh + " " + CellCh2 + " " + CellCh3 + ".");
		//print("Cell analysis parameters. Backreground Subtraction: "+ BGSZ + ". Unsharp Mask Size: "+ USSZ +". Unsharp Mask Weight: "+ USMW +". Cell area (um2): "+ size +".");
		print("  Cell analysis parameters. Background Subtraction: "+ BGSZ + ". Cell area (um2): "+ size1 +", "+ size2 +", "+size3+".");
		//" Maxima intensity threshold: "+ MaximaInt1 +".");
						
		File.mkdir(input + "4_Processed_Sections");
		File.mkdir(input + "4_Processed_Sections/Enhanced");
		File.mkdir(input + "4_Processed_Sections/Object_Detection_Validation");
		File.mkdir(CellCountOut);		
		File.mkdir(CellIntensityOut);
				
		//Process cell channels
		for (Ch_i = 0; Ch_i < 3; Ch_i++) {
			if (CellChans[Ch_i] > 0) {
				EnhanceAndFindMaxima(CellChans[Ch_i], CellMaxInts[Ch_i]);
	
			}	
		}      
		// Finish up
		print("Cell detection complete.");	
		maximaendtime = getTime();
		dif1 = (maximaendtime-maximastarttime)/1000;
		print("Cell detection processing time = "+ (dif1/60) +" minutes.");
		print("---------------------------------------------------------------------------------------------------------------------");		
}

/////////////////// CELL ANALYSIS: Manual count

if (CellAnalysisON == true && CellDetMethod == "Manual Cell Count") {
		maximastarttime = getTime();		
		print("Measuring intensities of manual cell locations...");
		//print("Resolution used for cell analysis: "+ FinalRes +"um/px. Channels used for detection: "+ CellCh + " " + CellCh2 + " " + CellCh3 + ".");
		print("  Channels used for detection: "+ CellCh + " " + CellCh2 + " " + CellCh3 + ".");
		//print("Cell analysis parameters. Backreground Subtraction: "+ BGSZ + ". Unsharp Mask Size: "+ USSZ +". Unsharp Mask Weight: "+ USMW +". Cell area (um2): "+ size +".");
						
		File.mkdir(CellIntensityOut);
		
		//Process cell channels // stack by stack times out, so have to process slice by slice

		for (Ch_i = 0; Ch_i < 3; Ch_i++) {
			if (CellChans[Ch_i] > 0) {
				measure_int_manual_cells(CellChans[Ch_i]);
			}	
		}      
			
		// Finish up
		print("Cell intensity measurements complete.");	
		maximaendtime = getTime();
		dif1 = (maximaendtime-maximastarttime)/1000;
		print("Cell intensity processing time = "+ (dif1/60) +" minutes.");
		print("---------------------------------------------------------------------------------------------------------------------");		

}


// Create enhanced images for THRESHOLD BASED PROJECTION ANALYSIS 
if (ProjectionTransformationON == true && ProjDetMethod == "Binary Threshold") {
	maximastarttime = getTime();
	
	print("Performing background subtraction for projection analysis...");
	print("  Channels used for detection: "+ ProCh + " " + ProCh2 + " " + ProCh3 + ".");
	File.mkdir(input + "4_Processed_Sections");
	File.mkdir(input + "4_Processed_Sections/Enhanced");
				
	//Process channel 1 // stack by stack times out, so have to process slice by slice
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (ProChans[Ch_i] > 0) {
			BGSubChannel(ProChans[Ch_i]) ;
		}	
	} 
	
	// Finish up
	print("Background subtraction complete.");	
	maximaendtime = getTime();
	dif1 = (maximaendtime-maximastarttime)/1000;
	print("Processing time = "+ (dif1/60) +" minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");	

}

/////////////////// STEP 3B: MAPPING CELLS INTO ATLAS SPACE /////////////////////////////////////////////////////////////////////////

// Resample for resolution and correct columns XYZ to ZYX for detected cells

if (CellAnalysisON == true && CellDetMethod != "No Cell Analysis" && AlignParamCheck < 3) {	
	print("Resampling cell locations to atlas...");

	if (File.exists(input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.1.txt") == 0 ) {
   		exit("Atlas registration files cannot be found - ensure atlas registration step has been performed.");
   	}

	//check and make directory
	if (File.exists(input + "5_Analysis_Output/Cell_Analysis") == 0) {
		File.mkdir(input + "5_Analysis_Output/Cell_Analysis");
	}
	
	//note for manual counting
	if (CellDetMethod == "Manual Cell Count") {				
		print("  ");
		print("  **Manual Cell Count selected: Ensure cell locations are saved as Cell_Points_Ch1/2/3/4.csv ");
		print("  and that files are saved in "+ CellPointsDir);
		print("  ");
	}
		
	//Resampled cells directory not always being made? Check and if not there, create.
	if (File.exists(input + "4_Processed_Sections/Resampled_Cells") == 0) {
		File.mkdir(input + "4_Processed_Sections/Resampled_Cells");
	}
	
	CountFiles = getFileList(CellPointsDir);
	CountFiles = Array.sort( CountFiles );
	CountRsFiles = getFileList(ResampledCellPointsDir);

	if (CountFiles.length == 0) {
		exit("No cell detection result files found in "+ CellPointsDir +"/nPlease ensure cell locations are saved as/nCell_Points_Ch1/2/3/4.csv");
	}

	if (CountFiles.length == CountRsFiles.length/2) {
		print("  Cell points already resampled to atlas space. If you wish to recreate, delete: "+ResampledCellPointsDir+" ");
	} else {
		for (Ch_i = 0; Ch_i < 3; Ch_i++) {
			if (CellChans[Ch_i] > 0) {
				print(" Resampling cell points "+CellChans[Ch_i]+" to atlas...");
	
				run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file");
				OpenAsHiddenResults(CellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".csv");
				TotalResults = nResults;
				//turn off save titles
				

				//Janky fix to remove titles occasionally causing errors in updated Fiji
				File.delete(CellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".csv")
				saveAs("Results", CellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".csv");
				close("Results"); 	
				OpenAsHiddenResults(CellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".csv");
								
				if (SampleType != "Light Sheet" && AtlasType != "Spinal Cord") {
					ResamplePoints();
					//taken out swap as now all atlases coronal		
					//SwapColumnsXYZ_ZYX(TableTitle, f);
					saveAs("Results", ResampledCellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".csv");
				}
				if (AtlasType == "Spinal Cord") {
					ResamplePointsSC();
					saveAs("Results", ResampledCellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".csv");
				}				
				close("Results"); 
				
				//open and resave to remove headings quickly
				OpenAsHiddenResults(ResampledCellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".csv");
				saveAs("Results", ResampledCellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".csv");
				
				close("Results");
				pointfilestring=File.openAsString(ResampledCellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".csv"); 
				//replace commas in point file with spaces
				pointfilestring = replace(pointfilestring, ",", " ");
				
				// Set a filename:
				CellFileOut = ResampledCellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".txt";
				// 1) Delete file if it exists - otherwise can produce error:
				if (File.exists(CellFileOut) == 1 ) {
					File.delete(CellFileOut);
				}
				// 2) Open file to write into
				WriteOut = File.open(CellFileOut);
	
				// 3) Print headings
				print(WriteOut, "point\n" + TotalResults + "\n" + pointfilestring);
			
				// 5) Close file
				File.close(WriteOut);
				
				close("*");
				print("  Cell locations resampled to atlas space.");	
			}
		}
	}
		// Read in Origin Point
		//Get index and origin - this is a negative value of a point transformed from the first slice of exp brain
		//Open transformed seed point
	OpenAsHiddenResults(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv");
	IndexOrigin=parseInt(getResult("Z", 0));
	IndexEnd=parseInt(getResult("Z", 1));
	close("Results");

// Ensure TransformParameters.0 is referring to correct location

	UpdateTransParamLocation0(input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.1.txt");

// Transform Cell Points
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (CellChans[Ch_i] > 0) {
			print("Transforming channel "+CellChans[Ch_i]+" cell locations to atlas space...");

			if (File.exists(input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Detected_Cells_Summary.csv")) {
				print("     Cell point transformation already performed. If you wish to rerun, delete directory: "+input + "5_Analysis_Output/Cell_Analysis/");
			} else {
			
				CellPoints = CreateCmdLine(ResampledCellPointsDir + "Cell_Points_Ch"+CellChans[Ch_i]+".txt");
				CellOut = CreateCmdLine(input + "5_Analysis_Output/Temp/Ch"+CellChans[Ch_i]+"Points/");
				
				TransformCellsCmd = Transformix +" -def "+CellPoints+" -tp "+TransP+" -out "+CellOut;
				CreateBatFile (TransformCellsCmd, input, "TransformixRun");
				runCmd = CreateCmdLine(input + "TransformixRun.bat");
				exec(runCmd);
				
				E49TransPointsToZYXcsv(input + "5_Analysis_Output/Temp/Ch"+CellChans[Ch_i]+"Points/outputpoints.txt", input + "5_Analysis_Output/Cell_Analysis", "C"+CellChans[Ch_i]+"_Aligned_Points");
				
				DeleteDir(input + "5_Analysis_Output/Temp/Ch"+CellChans[Ch_i]+"Points/");
				print("Cell locations successfully transformed to atlas space.");
			}
			
		}	
	} 

	DeleteFile(input+"TransformixRun.bat");	
	
	// Annotate Transformed point totals

	CHAstarttime = getTime();
	print("Creating cell locations atlas annotation table...");			
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (CellChans[Ch_i] > 0) {
			print("  Creating atlas region annotated count table for channel "+CellChans[Ch_i]+" ...");
			
			if (File.exists(input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Detected_Cells_Summary.csv")) {
				print("  Cell summary already performed. If you wish to rerun, delete directory: "+input + "5_Analysis_Output/Cell_Analysis/");
			} else {
				if (AtlasType == "Spinal Cord") {
					AnnotatePointsSpinalCord(input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Aligned_Points.csv", AtlasDir + "Annotation.tif", AtlasDir + "Atlas_Regions.csv", input + "4_Processed_Sections/Measured_Intensities/Cell_Points_with_intensities_Ch"+CellChans[Ch_i]+".csv", input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Detected_Cells_Summary.csv", input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Detected_Cells.csv",input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Detected_Cells_Segment_Summary.csv");
					cleanupROI();
					
					DeleteFile(input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Aligned_Points.csv");			
					print("  Annotation tables created.");
				} else {
					AnnotatePoints(input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Aligned_Points.csv", AtlasDir + "Annotation.tif", AtlasDir + "Atlas_Regions.csv", input + "4_Processed_Sections/Measured_Intensities/Cell_Points_with_intensities_Ch"+CellChans[Ch_i]+".csv", input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Detected_Cells_Summary.csv", input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Detected_Cells.csv");
					cleanupROI();
					DeleteFile(input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Aligned_Points.csv");			
					print("  Annotation tables created.");
				}
			}
		
		}
	}

	CHAendtime = getTime();
	dif = (CHAendtime-CHAstarttime)/1000;
	print("Cell annotation processing time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");

	// Create Cell Density Measurements
	
	TransformAnnotationDataset();
	
	print("Creating cell density table...");		
	DAstarttime = getTime();
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (CellChans[Ch_i] > 0) {
			print("Calculating cell density for channel "+CellChans[Ch_i]);
			if (AtlasType == "Spinal Cord") {
				//CellDensityFunction
				CreateCellDensityTableLRHemisphereFullResSpinalCord(CellChans[Ch_i]); 
			} else {
				//CreateCellDensityTableLRHemisphereFullRes(CellChans[Ch_i]);				
			}
		}	
	} 
	DAendtime = getTime();
	dif = (DAendtime-DAstarttime)/1000;
	print("Cell density table creation time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");
}

/////////////////// STEP 3C: CREATE CELL ANALYSIS VISUALIZATIONS /////////////////////////////////////////////////////////////////////////////////////////////////

if (CreateCellAnalysisVisON == true && AlignParamCheck < 3) {
	
	// Create voxelisation of points in template brain 
	CHMstarttime = getTime();
	print("Creating cell heatmaps...");
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (CellChans[Ch_i] > 0) {
			CreateCellHeatmap(CellChans[Ch_i]);
			
		}	
	} 	
	CHMendtime = getTime();
	dif = (CHMendtime-CHMstarttime)/1000;
	print("Cell heatmaps processing time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");


	// Create colourmap representation of point locations
	// create solid spheres in coloured atlas
	CPMstarttime = getTime();
	print("Creating cell points in atlas space...");
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (CellChans[Ch_i] > 0) {
			CreateCellPoints(CellChans[Ch_i]);
		}	
	} 	
	CPMendtime = getTime();
	dif = (CPMendtime-CPMstarttime)/1000;
	print("Cell point maps processing time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");


	// Create color display of cells in atlas
	CCDstarttime = getTime();
	print("Creating atlas colored cell images...");
	
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (CellChans[Ch_i] > 0) {
			print("  Creating atlas colored cell images for channel "+CellChans[Ch_i]);
	 		createColorCells(CellChans[Ch_i], input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Cell_Points.tif", input + "5_Analysis_Output/Cell_Analysis");
			OverlayColorCellsOnTemplate(input + "5_Analysis_Output/Cell_Analysis/C"+CellChans[Ch_i]+"_Atlas_Colored_Cells.tif", CellChans[Ch_i], input + "5_Analysis_Output/Cell_Analysis");
	 		print("  Colored cell images created.");
		}	
	} 	
 	
  	collectGarbage(10, 4);
	CCDendtime = getTime();
	dif = (CCDendtime-CCDstarttime)/1000;
	print("Atlas colored cell image creation time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");


	HMstarttime = getTime();
		
	AlignDir = input + "5_Analysis_Output/";
	print("Creating cell density heatmap images...");
 	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (CellChans[Ch_i] > 0) {
			if (AtlasType == "Spinal Cord") {
				CreateSCCellDensityHeatmapImage(CellChans[Ch_i]);
			} else {
				//CreateABACellDensityHeatmapJS(CellChans[Ch_i]);
			}
 		}
 	}
	close("*");
	HMendtime = getTime();
	dif = (HMendtime-HMstarttime)/1000;
	print("Atlas map intensity image creation: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");

	
}	

/////////////////// STEP 4: PERFORM PROJECTION ANALYSIS /////////////////////////////////////////////////////////////////////////////////////////////////

if (ProjectionTransformationON == true && ProjDetMethod != "No Projection Analysis" && AlignParamCheck < 3) {	

	print("Performing projection density analysis...");

	//New method for high-res analysis:
	//Create modified transform parameters to deform annotations onto full resolution data. Perform measurements this way.
	TransformAnnotationDataset();

	// Perfrom the density analysis

	DAstarttime = getTime();
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (ProChans[Ch_i] > 0) {
			print("Calculating density for channel "+ProChans[Ch_i]);
			if (AtlasType == "Spinal Cord") {
				CreateDensityTableLRHemisphereFullResSpinalCord(ProChans[Ch_i], ProMinInts[Ch_i]); 
			} else {
				CreateDensityTableLRHemisphereFullRes(ProChans[Ch_i], ProMinInts[Ch_i]);				
			}
		}	
	} 
	DAendtime = getTime();
	dif = (DAendtime-DAstarttime)/1000;
	print("Density analysis processing time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");
	close("*");
}

if (CreateABADensityHeatmapON == true && ProjDetMethod != "No Projection Analysis" && AlignParamCheck < 3) {
	HMstarttime = getTime();
	AlignDir = input + "5_Analysis_Output/";
	print("Creating atlas density heatmaps...");
	
	for (Ch_i = 0; Ch_i < 3; Ch_i++) {
		if (ProChans[Ch_i] > 0) {
			if (AtlasType == "Spinal Cord") {
				print(" Creating density heatmap for channel "+ProChans[Ch_i]);
				CreateSCDensityHeatmap(ProChans[Ch_i],"C"+ProChans[Ch_i]+"_Region_and_Segment_Projection_Density.csv", "C"+ProChans[Ch_i]+"_Atlas_Density_Heatmap");
				print(" Creating relative density heatmap for channel "+ProChans[Ch_i]);
				CreateSCDensityHeatmap(ProChans[Ch_i],"C"+ProChans[Ch_i]+"_Region_and_Segment_Projection_Relative_Density.csv", "C"+ProChans[Ch_i]+"_Atlas_Relative_Density_Heatmap");
				
			} else {
				CreateABADensityHeatmapJS(ProChans[Ch_i]);
			}
			close("*");
		}	
	} 
	
	HMendtime = getTime();
	dif = (HMendtime-HMstarttime)/1000;
	print("Atlas density heatmap image creation time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");
}			
	
// Transform Binary Images of projections and also create coded display of projections. C"+Channel+"_Sagittal_Binary.tif"

//Perform Transformation and create parameter files for transforming binary isotropic datasets to atlas

if (AtlasType == "Spinal Cord") {
	CreateColorDensityImagesON = false;
}
	
if (CreateColorDensityImagesON == true && ProjDetMethod != "No Projection Analysis" && AlignParamCheck < 3) {
	CDstarttime = getTime();
	print("Creating atlas colored projection density images...");
	
	VisRegCheck = PerformReverseTransformationForProjections();
	
	File.mkdir(TransformedProjectionDataOut);
	if (VisRegCheck == 0) {	
		for (Ch_i = 0; Ch_i < 3; Ch_i++) {
			if (ProChans[Ch_i] > 0) {
				//after running test that it can perform if files missing for registered direcotry
				VisRegCheck = TransformBinaryDataToAtlas(ProChans[Ch_i]);
				if (VisRegCheck == 0) {	
					createColorProjections(ProChans[Ch_i]);
				
				 	OverlayColorProjectionsOnTemplate(TransformedProjectionDataOut+"C"+ProChans[Ch_i]+"_Atlas_Colored_Projections.tif", ProChans[Ch_i], TransformedProjectionDataOut);
				}
				}
			}	
		} 	 	
		CDendtime = getTime();
		dif = (CDendtime-CDstarttime)/1000;
		print("Atlas colored projection density image creation: ", (dif/60), " minutes.");	
		print("---------------------------------------------------------------------------------------------------------------------");	
	} else {
		print("Atlas colored projection density images could not be created. Check registration quality.");	
		print("---------------------------------------------------------------------------------------------------------------------");	


}	

/////////////////// STEP 6: TRANSFORM RAW DATA TO ABA /////////////////////////////////////////////////////////////////////////////////////////////////

if (RawChannelTransformON == true && AlignParamCheck < 3) {	

	if (AtlasType == "Spinal Cord") {
		//print("Transforming raw data into atlas space not currently available for spinal cord data.");


	} else {
		
		VisRegCheck = TransformRawDataToAtlas();
	}	
	 		
}
		  
/////////////////// STEP 5: PERFORM INTENSITY MEASUREMENTS IN ANNOTATED REGIONS /////////////////////////////////////////////////////////////////////////////////////////////////
if (IntensityMeasureInABAON == true && AlignParamCheck < 3) {
	//Count number of channel folders in Registered Directory
	
	print("Performing intensity measurements in annotated regions...");

	TransformAnnotationDataset();
	
	ChNum = CountSubFolders(input+ "/3_Registered_Sections/");

	//Count number of registered slices
	RegSectionsCount = getFileList(input+ "/3_Registered_Sections/1/");	
	RegSectionsCount = RegSectionsCount.length;
	
	//Perform measurements
	print("Measuring fluorescent intensities for each annotated region for each channel. Please allow 5-10min per channel.");
	DAstarttime = getTime();

	
	
	for(j=1; j<ChNum+1; j++) {	
	 	print(" Measuring fluorescent intensities for each brain region in channel "+j+".");

		if (AtlasType == "Spinal Cord") {
			ProAnRes = 10; //Temp override - or leave in place
			MeasureIntensitiesLRHemisphereFullResSpinalCord(j);
		} else {
			ProAnRes = 25; //Temp override - or leave in place
			MeasureIntensitiesLRHemisphereFullRes(j);			
		}	
	 	
	}

	DAendtime = getTime();
	dif = (DAendtime-DAstarttime)/1000;
	print("Region intensity measurement processing time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");
}
close("*");

/////////////////// STEP 5B: CREATE INTENSITY MAPS /////////////////////////////////////////////////////////////////////////////////////////////////

if (CreateIntensityMapsON == true && AlignParamCheck < 3) {
	HMstarttime = getTime();
	
	//Count number of channel folders in Registered Directory
	ChNum = CountSubFolders(input+ "/3_Registered_Sections/");
		
	AlignDir = input + "5_Analysis_Output/";
	print("Creating atlas map intensity images...");
 	for(j=1; j<ChNum+1; j++) {	
	
		if (AtlasType == "Spinal Cord") {
			CreateSCIntensityImage(j);
		} else {
			CreateABAIntensityHeatmapJS(j);
		}
	
 	}
	close("*");
	HMendtime = getTime();
	dif = (HMendtime-HMstarttime)/1000;
	print("Atlas map intensity image creation: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");
}

/////////////////// STEP 7: EXTRACT SPECIFIC REGIONS AT FULL RESOLUTION /////////////////////////////////////////////////////////////////////////////////////////////////

if (FullResExtractON == true && AlignParamCheck < 3) {
	// Make sure annotations have been trasnformed.
	TransformAnnotationDataset();
	// Extract each region.
	AnnotatedRegionExtraction();
	
}

/////////////////// FINISH UP /////////////////////////////////////////////////////////////////////////////////////////////////
selectWindow("Log");
setLocation(500, 300);
FinalCleanup();
endtime = getTime();
dif = (endtime-starttime)/1000;
print("Total processing time: ", (dif/60), "minutes.");
print("Analysis type: " + AtlasType);
print("Atlas used for analysis: " + AtlasName);
print("---------------------------------------------------------------------------------------------------------------------");
print("- - - " +BrainJVer+ " - - -");
print("---------------------------------------------------------------------------------------------------------------------");
print("");
print("Bregma coordinates have been provided by comparing multiple landmarks to determine the following linear transformations:");
print("   Bregma_AP = (ZPosition*25-5350)*-1   Bregma_DV = (YPosition*25-470)*-1   Bregma_ML = XPosition*25-5700");

if (AlignParamCheck == 3) {
	print("***Warning: Alignment to template brain failed all three attempts.");
	print("   Please check quality of the dataset and correct or replace any damaged sections.");
	print("");
}

if (AlignParamCheck > 0 && AlignParamCheck < 3) {
	print("***Note: Initial alignment to template brain using strict parameters failed.");
	print("   More lenient parameters were used and were successful but alignment may not be ideal. This is typically due to damaged sections"); 
	print("   Please check quality of the registration by inspecting the Template_Brain_Aligned.tif image and correct or replace any damaged sections.");
	print("");
}

if (VisRegCheck > 0) {
	print("***Warning: Registration process for generating visualizations of raw data and projections in atlas space failed.");
	print("   Visualizations of projections and raw data in atlas space won't be available but all other analysis is unaffected");
	print("   To resolve this issue, check \5_Analysis_Output\template_brain_aligned.tif and explore ways to improve registration (e.g. replace damaged sections)");
	print("");
}

if (CellPlotCheck > 0) {
	print("***Note: "+CellPlotCheck+" cells could not be plotted into the atlas.");
	print("   This is likely due to the inaccuracies in the registration, especially towards the posterior edge of the cerebellum."); 
	print("   If you are seeing this message check the quality of the registration by inspecting the Template_Brain_Aligned.tif image.");
	print("");
}
selectWindow("Log");
// time stamp log to prevent overwriting.
getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
saveAs("txt", input+"/Atlas_Analysis_Log_" + year + "-" + (month+1) + "-" + dayOfMonth + "_" + hour + "-" + minute + ".txt");


}
}
}

wait(500);
close("Results");


/////////////////// FUNCTIONS /////////////////////////////////////////////////////////////////////////////////////////////////

function RegisterSections() {

//import and register channel 1 / autoF or DAPI > Save and use as reference for other channels
	//Create tmp file to store translation for DAPI registration
	
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	//tmpfile  = getDirectory("temp");
	tmpfilename = "Translation-" + year + "-" + month + "-" + dayOfMonth + "_" + hour + "-" + minute + "-" + second + ".txt";
	tmpfile = input + tmpfilename;
					
	// Find out how many channels:
	ChNum = CountFolders(input+ "/1_Reformatted_Sections/");
	ChArray = NumberedArray(ChNum);
	
	//import and register channels
	
	rawSections = getFileList(input+"/1_Reformatted_Sections/"+AlignCh);
	rawSections = Array.sort( rawSections);
	Section1 = rawSections[0];		

	open(input + "/1_Reformatted_Sections/1/" + Section1);

	//inserted values to stop 	'['expected in line 199: error
	width = 1;
	height = 1;
	ChNumz = 1;
	slices = 1;
	frames = 1;
	
	getDimensions(width, height, ChNumz, slices, frames);
	getPixelSize(unit, W, H);	
	close();

	//Determine final scale for import
	finalscale = RegRes/AtlasResXY*100;
	print(" Registration image will be scaled at "+finalscale+"% to match "+AtlasResXY+"micron/pixel lateral resolution of atlas.");
		
	//Note if scale <than 5 it won't import correctly so import at 5% and rescale as necessary OR import and then rescale			

	if (finalscale < 5) {
		run("Image Sequence...", "open=["+ input + "/1_Reformatted_Sections/" + AlignCh + "/" + Section1 + "] scale=5 sort");
		rename("DAPI");
		newfinalscale = ((finalscale * 20)/100);
		run("Scale...", "x="+newfinalscale+" y="+newfinalscale+" z=1.0 interpolation=Bilinear average process create title=DAPIsm");
		close("DAPI");
		selectWindow("DAPIsm");
		
	} else {
		run("Image Sequence...", "open=["+ input + "/1_Reformatted_Sections/" + AlignCh + "/" + Section1 + "] scale="+finalscale+" sort");
	}
			
	
	getDimensions(wz, hz, Chz, slices, frames);	
	rename("DAPI");		
	selectWindow("DAPI");
	run("Subtract...", "value="+BGround+" stack");
	run("Enhance Contrast...", "saturated=1 process_all use");
	getDimensions(Dwidth, Dheight, DChNum, Dslices, Dframes);
	print(" Registration dataset: " + Dwidth + " X " + Dheight + " with " + Dslices + " slices.");
	if (Dslices < StartSection) {
		print("User selected section for registration = "+StartSection+". This is too high, selecting middle section (section "+parseInt(Dslices/2)+") for registration");
		StartSection = parseInt(Dslices/2);
	}
	setSlice(StartSection);
	// Enhance contrast and run attenuation correction
	// This could create a problem for second pass registration - potentially disabled if using fiducial markers and second pass.
	run("Enhance Contrast...", "saturated=5 normalize");
	List.setCommands;
	if (List.get("Attenuation Correction")!="") {
	      print(" Correcting for intensity differences accross sections.");    
	      run("Attenuation Correction", "opening=3 reference="+StartSection);
	      close("DAPI");
	      close("Background of DAPI");
	      selectWindow("Correction of DAPI");
	      rename("DAPI");
	        
	} else {
		print(" Attenuation Correction not installed. Registration will still occur, but please install for best results.");
	}
	
	run("MultiStackReg", "stack_1=DAPI action_1=Align file_1=[" + tmpfile + "] stack_2=None action_2=Ignore file_2=[] transformation=[Rigid Body] save multiple");
	if (SecondPass == true) {
		tmpfilename2 = "Translation-Pass2-" + year + "-" + month + "-" + dayOfMonth + "_" + hour + "-" + minute + "-" + second + ".txt";
		tmpfile2 = input + tmpfilename2;
		run("MultiStackReg", "stack_1=DAPI action_1=Align file_1=[" + tmpfile2 + "] stack_2=None action_2=Ignore file_2=[] transformation=[Rigid Body] save multiple");

	}
	
	//Fix Scaling
	//Used to be x10 scale down image then x10 scale up transformation. Now based on scale percent so: if 2 and 20 it would 10. if 2 and 10 it would be 5	
	TransScale = 100/finalscale;
	run("Properties...", "unit="+unit+" pixel_width="+(W*TransScale)+" pixel_height="+(H*TransScale)+" voxel_depth="+ZCut);

	//Create a MIP and binary dilate crop - keep this ROI to crop datasets on import
	if (CropOn == true){
		
		run("Z Project...", "projection=[Max Intensity]");
		MAX = getImageID();
		run("Scale...", "x="+TransScale+" y="+TransScale+" interpolation=Bilinear average create");

		SCALE = getImageID();
		selectImage(SCALE);
		run("Colors...", "foreground=white background=black selection=yellow");
		setOption("BlackBackground", true);
		if (List.get("Attenuation Correction")!="") {
		 	run("Auto Threshold", "method=Mean white");
			setOption("BlackBackground", true);
		} else {
			setMinAndMax(0, 50);
			run("Apply LUT");
			run("Convert to Mask");
			
		}
		run("Options...", "iterations=3 count=1 black");

		checkbinaryforinversion();
		run("Analyze Particles...", "size=500000-Infinity display add");	
		roiManager("Save", input+"/BrainROI.zip");
		run("Clear Results");
		roiManager("Delete");
		close();
		
		selectImage(MAX);
		run("Colors...", "foreground=white background=black selection=yellow");
		setOption("BlackBackground", true);
		if (List.get("Attenuation Correction")!="") {
		 	run("Auto Threshold", "method=Mean white");
			setOption("BlackBackground", true);
		} else {
			setMinAndMax(0, 50);
			run("Apply LUT");
		}
		
		run("Options...", "iterations=3 count=1 black");
		run("Convert to Mask");

		checkbinaryforinversion();
		run("Analyze Particles...", "size=500000-Infinity display add");
		roiManager("Save", input+"/BrainROIsm.zip");
		run("Clear Results");
		roiManager("Delete");
		close();
	}
	
	// Create DAPI/AF 25um dataset for atlas alignment
	selectWindow("DAPI");
	
	if (CropOn == true){
		setBatchMode(false);
		roiManager("Open", input+"/BrainROIsm.zip");
		roiManager("Select", 0);
		run("Crop");
		roiManager("Select", 0);
		roiManager("Delete");
		selectWindow("DAPI");
		run("Select None");
		setBatchMode(true);
	}
				
	if (FullResDAPI == 0 && ChNum > 1) {
		File.mkdir(RegDir+AlignCh);
		rename("Ch");
		run("Image Sequence... ", "format=TIFF save=["+input+"/3_Registered_Sections/"+AlignCh+"/0000.tif]");
		rename("DAPI");			
	}
	
	//run("Median...", "radius=1 stack");
	run("Properties...", "unit=micron voxel_depth="+ZCut+"");

	// Special Modification for spinal cord analysis - to stretch length to known length of isolated regions
	if (AtlasType == "Spinal Cord" && SCSegRange.length > 1) {
		//Get the start and end slice based on the segment information provided
		SegmentCSV = File.openAsString(AtlasDir + "Segments.csv");
		SegmentCSVRows = split(SegmentCSV, "\n"); 
		for(i=0; i<SegmentCSVRows.length; i++){
			// Find Start Slice
			if(matches(SegmentCSVRows[i],".*"+SCSegRange[0]+".*") == 1 ){
				Row = split(SegmentCSVRows[i], ",");
				SCStartSlice = parseInt(Row[2]);
			}
			if(matches(SegmentCSVRows[i],".*"+SCSegRange[1]+".*") == 1 ){
				Row = split(SegmentCSVRows[i], ",");
				SCEndSlice = parseInt(Row[3]);
			}
		}
		SCTotalSlices = SCEndSlice-SCStartSlice;
		SCRawSlices = nSlices;
		run("Reslice Z", "new="+ZCut*nSlices/SCTotalSlices);			
		print(" Registration dataset contains " + SCRawSlices + " slices. Segment range is " + SCSegRange[0] + " to  "+ SCSegRange[1] +", a total of "+ SCTotalSlices + " slices. Compensating to match.");
		
	} else {
		run("Reslice Z", "new="+AtlasResZ);
	}
	rename("Resliced");
	close("DAPI");
	selectWindow("Resliced");
	run("16-bit");
	resetMinAndMax();
	run("Enhance Contrast...", "saturated=0.01 process_all use");
	run("Apply LUT", "stack");
	if (List.get("Attenuation Correction")!="") {
		rename("DAPI");
	    run("Attenuation Correction", "opening=3 reference=1");
	    close("DAPI");
	    close("Background of DAPI");
	    selectWindow("Correction of DAPI");
	    rename("DAPI");
	}
	run("Properties...", "unit=micron pixel_width="+AtlasResXY+" pixel_height="+AtlasResXY+" voxel_depth="+AtlasResZ);
	saveAs("Tiff", input+"3_Registered_Sections/DAPI_25.tif");

	setAutoThreshold("Li dark");
	run("Convert to Mask", "method=Li background=Dark calculate black");
	run("Dilate", "stack");
	run("Dilate", "stack");
	saveAs("Tiff", input+"/3_Registered_Sections/DAPI_25_Mask.tif");
	close();

	regtime = getTime();
	dif1 = (regtime-starttime)/1000;
	print("Registration of downsampled dataset complete. (" + (dif1/60) + " minutes)");
	
	print("Translating channels at full resolution...");
	print(" Please allow ~", parseInt((dif1*5.5)/60), "minutes per channel for translation of remaining channels.");
	
	collectGarbage(Dslices, 4);
	
	if (SecondPass == false) {
	// Multiply transformation file by downscale factor
		filestring=File.openAsString(tmpfile); 		
		rows=split(filestring, "\n"); 
	
		TransformRowsArray=newArray(0);
		for(i=0; i<rows.length; i++){ 
			if(matches(rows[i],".*RIGID_BODY.*") == 1 ){
				TransformRowsArray = append(TransformRowsArray, i);
			}
		}	
		editrows1=newArray(2,3,4);
		editrows2=newArray(6,7,8);

		for(i=0; i<TransformRowsArray.length; i++){ 
			for(j=0; j<editrows1.length; j++){
				transformline=TransformRowsArray[i]+editrows1[j];
				//print(rows[transformline]);	
				columns=split(rows[transformline],"\t");
				columns[0] = parseFloat(columns[0])*TransScale;
				columns[1] = parseFloat(columns[1])*TransScale;
				rows[transformline] = d2s(columns[0],18) + "\t" + d2s(columns[1],18);
				//print(rows[transformline]);	
			}	
			for(j=0; j<editrows2.length; j++){
				transformline=TransformRowsArray[i]+editrows2[j];
				//print(rows[transformline]);	
				columns=split(rows[transformline],"\t");
				columns[0] = parseFloat(columns[0])*TransScale;
				columns[1] = parseFloat(columns[1])*TransScale;
				rows[transformline] = d2s(columns[0],3) + "\t" + d2s(columns[1],3);
				//print(rows[transformline]);	
			}	
		}
		
		filestringout = rows[0] + "\n";
		for(i=1; i<rows.length; i++){
			filestringout= filestringout + rows[i] +"\n";
		}
		run("Text Window...", "name=TransformationFile");
		print("[TransformationFile]", filestringout);
		
		run("Text...", "save=["+tmpfile +"]");
		close(tmpfilename);
	}
	if (SecondPass == true) {
		// Multiply transformation file by downscale factor
		filestring=File.openAsString(tmpfile); 
		
		rows=split(filestring, "\n"); 
		
		TransformRowsArray=newArray(0);
		for(i=0; i<rows.length; i++){ 
			if(matches(rows[i],".*RIGID_BODY.*") == 1 ){
				TransformRowsArray = append(TransformRowsArray, i);
			}
		}
		
		editrows1=newArray(2,3,4);
		editrows2=newArray(6,7,8);
		
		for(i=0; i<TransformRowsArray.length; i++){ 
			for(j=0; j<editrows1.length; j++){
				transformline=TransformRowsArray[i]+editrows1[j];
				//print(rows[transformline]);	
				columns=split(rows[transformline],"\t");
				columns[0] = parseFloat(columns[0])*TransScale;
				columns[1] = parseFloat(columns[1])*TransScale;
				rows[transformline] = d2s(columns[0],18) + "\t" + d2s(columns[1],18);
				//print(rows[transformline]);	
			}	
			for(j=0; j<editrows2.length; j++){
				transformline=TransformRowsArray[i]+editrows2[j];
				//print(rows[transformline]);	
				columns=split(rows[transformline],"\t");
				columns[0] = parseFloat(columns[0])*TransScale;
				columns[1] = parseFloat(columns[1])*TransScale;
				rows[transformline] = d2s(columns[0],3) + "\t" + d2s(columns[1],3);
				//print(rows[transformline]);	
			}	
		}
		
		filestringout = rows[0] + "\n";
		for(i=1; i<rows.length; i++){
			filestringout= filestringout + rows[i] +"\n";
		}
		run("Text Window...", "name=TransformationFile");
		print("[TransformationFile]", filestringout);
		
		run("Text...", "save=["+tmpfile +"]");
		close(tmpfilename);


	// Multiply transformation file by downscale factor
		filestring=File.openAsString(tmpfile2); 
		
		rows=split(filestring, "\n"); 
		
		TransformRowsArray=newArray(0);
		for(i=0; i<rows.length; i++){ 
			if(matches(rows[i],".*RIGID_BODY.*") == 1 ){
				TransformRowsArray = append(TransformRowsArray, i);
			}
		}
		
		editrows1=newArray(2,3,4);
		editrows2=newArray(6,7,8);
		
		for(i=0; i<TransformRowsArray.length; i++){ 
			for(j=0; j<editrows1.length; j++){
				transformline=TransformRowsArray[i]+editrows1[j];
				//print(rows[transformline]);	
				columns=split(rows[transformline],"\t");
				columns[0] = parseFloat(columns[0])*TransScale;
				columns[1] = parseFloat(columns[1])*TransScale;
				rows[transformline] = d2s(columns[0],18) + "\t" + d2s(columns[1],18);
				//print(rows[transformline]);	
			}	
			for(j=0; j<editrows2.length; j++){
				transformline=TransformRowsArray[i]+editrows2[j];
				//print(rows[transformline]);	
				columns=split(rows[transformline],"\t");
				columns[0] = parseFloat(columns[0])*TransScale;
				columns[1] = parseFloat(columns[1])*TransScale;
				rows[transformline] = d2s(columns[0],3) + "\t" + d2s(columns[1],3);
				//print(rows[transformline]);	
			}	
		}
		
		filestringout = rows[0] + "\n";
		for(i=1; i<rows.length; i++){
			filestringout= filestringout + rows[i] +"\n";
		}
		run("Text Window...", "name=TransformationFile");
		print("[TransformationFile]", filestringout);
		
		run("Text...", "save=["+tmpfile2 +"]");
		close(tmpfilename2);
		

}


	// Open and align additional channels

	for(j=1; j<ChArray.length+1; j++) {
		if (FullResDAPI == 0 && j == AlignCh && ChArray.length > 1) {
			print(" Not translating channel "+j+" at full resolution as only lower resolution required for DAPI/Autofluorescence.");
		} else {
			
			print(" Translating channel "+j+" at full resolution...");
			Sections = getFileList(input+"/1_Reformatted_Sections/"+j);
			Sections = Array.sort( Sections);
			Section = Sections[0];	
	
			collectGarbage(Dslices, 4);
			run("Image Sequence...", "open=["+ input + "/1_Reformatted_Sections/" + j + "/" + Section + "] scale="+100+" sort");
			
		
			//Fix Scaling
			run("Properties...", "unit="+unit+" pixel_width="+W+" pixel_height="+H+" voxel_depth="+ZCut);
			rename("Ch");
			run("MultiStackReg", "stack_1=Ch " 
			+ "action_1=[Load Transformation File] file_1=[" + tmpfile + "] "
			+ "stack_2=None action_2=Ignore file_2=[] transformation=[Rigid Body]");

			if (SecondPass == true) {
				run("MultiStackReg", "stack_1=Ch " 
				+ "action_1=[Load Transformation File] file_1=[" + tmpfile2 + "] "
				+ "stack_2=None action_2=Ignore file_2=[] transformation=[Rigid Body]");
			}
			
			//File.mkdir(input + "Ch_"+j+"_Registered");
			run("Properties...", "unit=micron voxel_depth="+ZCut+"");
					
			if (CropOn == true){
				setBatchMode(false);
				roiManager("Open", input+"/BrainROI.zip");
				roiManager("Select", 0);
				run("Crop");
				roiManager("Select", 0);
				roiManager("Delete");
				selectWindow("Ch");
				run("Select None");
				setBatchMode(true);
			}
		
			//saveAs("Tiff", input+"/3_Registered_Slices/Ch"+j+"_registered.tif");
			
			File.mkdir(RegDir+j);
			run("Image Sequence... ", "format=TIFF save=["+input+"/3_Registered_Sections/"+j+"/0000.tif]");
			close();
			
			collectGarbage(Dslices, 4);
		}
	}

	// Cleanup!
	DeleteFile(input+"/BrainROIsm.zip");
	DeleteFile(input+"/BrainROI.zip");
	DeleteFile(tmpfile);
	
}

function CreateOriginPoints() {
	print("Creating origin points...");
	//open exp brain, create start point and final point then save as csv
	open(input + "/3_Registered_Sections/DAPI_25.tif");
	close("Results");
	
	// measurement settings
	run("Properties...", "channels=1 unit=micron pixel_width=1 pixel_height=1");
	run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file");
	run("Set Measurements...", "centroid stack redirect=None decimal=3");

	//inserted values to stop 	'['expected in line 798: error
	//Xwidth = 1;
	//Yheight = 1;
	//slices = 1;
	
	getDimensions(Xwidth, Yheight, _, slices, _);
	setSlice(1);
	setTool("multipoint");
	// Left / A Origin Point
	makePoint(Xwidth/2, Yheight/2);
	run("Measure");
	// Right / P Origin Point
	setSlice(slices);
	makePoint(Xwidth/2, Yheight/2);
	run("Measure");
	
	selectWindow("Results");	
	saveAs("Results", input + "5_Analysis_Output/Transform_Parameters/OriginPoints/OriginPoints.csv");
	close("Results");
	close("DAPI_25.tif");
	
	filestring=File.openAsString(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/OriginPoints.csv"); 
	rows=split(filestring, "\n"); 
	for(i=0; i<rows.length; i++){ 
		//Clean up commas
		rows[i] = replace(rows[i], ",", " ");
	}

	run("Text Window...", "name=ResampledPoints");
	print("[ResampledPoints]", "point\n");
	//Weird behaviour with ImageJ 1.53c - sometimes rows 3 sometimes 2
	//print("[ResampledPoints]", rows.length + "\n");
	
print("[ResampledPoints]", 2 + "\n");
	if (rows.length == 3) {
		for(i=1; i<rows.length; i++){ 
			print("[ResampledPoints]", rows[i] + "\n");
		}
	} else {
		for(i=0; i<rows.length; i++){ 
			print("[ResampledPoints]", rows[i] + "\n");
		}
	}
	selectWindow("ResampledPoints");
	run("Text...", "save=["+input +"5_Analysis_Output/Transform_Parameters/OriginPoints/OriginPoints.txt]");
	close("OriginPoints.txt");
	print("  Origin points created.");
}


function NumberedArray(maxnum) {
	//use to create a numbered array from 1 to maxnum, returns numarr
	//e.g. ChArray = NumberedArray(ChNum);
	numarr = newArray(maxnum);
	for (i=0; i<numarr.length; i++){
		numarr[i] = (i+1);
	}
	return numarr;
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
			//roiManager("Combine");
			roiManager("Delete");
			ROIarrayMain=newArray(0);
			CountROImain=0;
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

function checkbinaryforinversion() {
	// correction for images that are inverted (sometimes occurs if user has opened and resaved slice in imageJ with different settings)
	//** this part needs to be corrected for spinal cords image size	REMOVE?
	run("Set Measurements...", "mean redirect=None decimal=3");
	getDimensions(wsm, hsm, ChNumsm, slicessm, framessm);
	makeRectangle(1, 1, 2, 2);
	run("Measure");
	boxint1 = getResult("Mean");
	run("Clear Results");
		
	makeRectangle(1, hsm-5, 2, 2);
	run("Measure");
	boxint2 = getResult("Mean");
	run("Clear Results");
	
	makeRectangle(wsm-5, hsm-5, 2, 2);
	run("Measure");
	boxint3 = getResult("Mean");
	run("Clear Results");
	
	makeRectangle(wsm-5, 1, 2, 2);
	run("Measure");
	boxint4 = getResult("Mean");
	run("Clear Results");
	
	boxint = ((boxint1+boxint2+boxint3+boxint4)/4);
	
	if (boxint > 191) {
		run("Select None");
		run("Invert");
	} else {
		run("Select None");
	}
}

function CreateProbabilityMap(CellChan) {	
	//CreateProbabilityMap(CellChan - e.g CellCh);
	//orig - (dir, classifier, EnOut, ProbOut, MaskOut, MaskThresh) {	
	//batch file creation prep

	print("Creating Ilastik probability images for channel "+CellChan+"...");
	dir = RegDir+CellChan+"/";
	classifier = "Ilastik_Project_Channel_"+CellChan+".ilp";	
	
	File.mkdir(input + "4_Processed_Sections/Enhanced/"+CellChan);	
	EnOut = input + "4_Processed_Sections/Enhanced/"+CellChan+"/";
	File.mkdir(input + "4_Processed_Sections/Probability_Masks/"+CellChan);
	ProbOut = input + "4_Processed_Sections/Probability_Masks/"+CellChan+"/";
	if (ilastikmaskON == false) {
		MaskOut = 0;
		MaskThresh = 0;
	} else {
		File.mkdir(input + "4_Processed_Sections/Ilastik_Binary_Masks/"+CellChan);
		IlastikMasks = input + "4_Processed_Sections/Ilastik_Binary_Masks/"+CellChan+"/";
		MaskThresh = ilastikmaskthresh;
	}
	
	//Ilastik Batch Processing
	ProjectCh = ClassDir + classifier;
	ProjectCh = replace(ProjectCh, "\\", "/");

	//ProjectCh1 = "C:/Users/Luke Hammond/Desktop/new illastik/Pixel Class neuron processes and background 16bit.ilp"
	ProjectCh = q + ProjectCh + q;

	ProbOutDir = ProbOut;
	ProbOut = replace(ProbOut, "\\", "/");
	ProbOut = q + ProbOut + "{nickname}_Probabilities.tif" + q;
	ilcommand = ilastik +" --headless --project="+ProjectCh+" --output_filename_format=" + ProbOut;
	EnOut2 = replace(EnOut, "\\", "/");
	MaskOut2 = replace(MaskOut, "\\", "/");

	//process sections
	
	Sections = getFileList(dir);
	Sections = Array.sort(Sections);	

	ExistingProbs = getFileList(ProbOutDir);
	
	if (ExistingProbs.length == Sections.length) {
		print("     Ilastik probability images already created. If you wish to recreate, delete directory: "+ProbOutDir+" ");
	} else {
		if (File.exists(ClassDir + classifier) == 0 ) {
			waitForUser("Cannot find ilastik .ilp file:" + ClassDir + classifier);
		}
	
		cleanupROI();
		
		ExistingEnhanced =  getFileList(EnOut);
		
		if (ExistingEnhanced.length == Sections.length) {
			print("  Enhanced images already created. If you wish to recreate, delete directory: "+EnOut+" ");
		
		} else {
			print("  Enhancing images for Ilastik segmentation...");
			run("Image Sequence...", "open=["+ dir + Sections[0] + "] scale=100 sort");
			getDimensions(Dwidth, Dheight, DChNum, Dslices, Dframes);
		
			if (BGSZ > 0) {
				run("Subtract Background...", "rolling="+ BGSZ + " stack");
			}
			run("Image Sequence... ", "format=TIFF save=["+EnOut+"Section0000.tif]");

			if (MaskOut != 0) {
				setThreshold(MaskThresh, 65535);
				setOption("BlackBackground", true);
				run("Convert to Mask", "method=Default background=Dark black");
				print(EnOut);
				print(MaskOut);
				run("Image Sequence... ", "format=PNG save=["+MaskOut+"Section0000.png]");
				
			}
			
			close();
			collectGarbage(Dslices, 4);
			print("   Complete.");
		}
	
		
		EnSections = getFileList(EnOut);
		EnSections = Array.sort(EnSections);

		MaskSections = getFileList(MaskOut);
		MaskSections = Array.sort(MaskSections);
		
		print("Performing Ilastik pixel classification...");
		
		
		for(i=0; i<EnSections.length; i++) {	
			EnSection = EnSections[i];
			if (MaskOut != 0) {
				MaskSection = MaskSections[i];
			}
			cleanupROI();
			print("Performing Ilastik pixel classification on section " + (i+1) + " of " + (EnSections.length) + ".");
			print("  ");
			
			if (MaskOut == 0) { 
				NameFull = EnOut2 + EnSection;
				NameFull = q + NameFull + q;

			} else {
				NameFull = " --raw_data " + q + EnOut2 + EnSection + q + " --prediction_mask " + q + MaskOut2 + MaskSection + q;
			}
			
			ilcommandbatch = ilcommand +" " + NameFull;

			run("Text Window...", "name=Batch");
			//print("[Batch]", "@echo off" + "\n");
			print("[Batch]", ilcommandbatch);
			// check - will this overwrite if already present?
			run("Text...", "save=["+inputfixed +"/Ilastikrun.bat]");
			selectWindow("Ilastikrun.bat");
			run("Close"); 
			runilastik = input + "Ilastikrun.bat";
			runilastik = replace(runilastik, "\\", "/");
			runilastik = q + runilastik + q;
			exec(runilastik);
			
			results = getFileList(ProbOut);
			if (results.length < i) {
				wait(1000);
				results = getFileList(ProbOut);
				
			}
				
			// add in validation creation image step, otherwise close
			//if(validation = true) {
					//open probability cell channel - expects cells REd Processes Green Background Blue
				//merge with enhanced
				//save in validation folder
	
		}
	
	}	

	print("  Complete.");
	DeleteFile(input+"Ilastikrun.bat");

	//Option to Delete Enhanced Channel?
				
			
	//Preprocessing of Slices

	//print("\\Clear");
	//print("@echo off");
	//print(ilcommand);
	//selectWindow("Log");
	//saveAs("txt", input +"/Ilastikrun.txt");
	//File.rename(input+"/Ilastikrun.txt", input+"/Ilastikrun.bat");

	//exec("cmd", "/c", "start", "\"Window\"", runilastik);
	//exec("cmd", "/c", "start", "\"Window\"", "\"C:/Users/Luke Hammond/Desktop/new illastik/batch test/Ilasticrun.bat\"");

	//at end must delete all processed images and just keep probabilities - no, but give option, instead overlay detection with enhanced

	//Alternative - for each slice run ilastik seperately - this will keep total space required down BUT take longer

}

function CreateProbabilityMapBatch(CellChan) {	
	//CreateProbabilityMap(CellChan - e.g CellCh);
	//orig - (dir, classifier, EnOut, ProbOut, MaskOut, MaskThresh) {	
	//batch file creation prep
	//NOTE - currently not supporting masks in ilastik 

	print("Creating Ilastik probability images for channel "+CellChan+"...");
	dir = RegDir+CellChan+"/";
	classifier = "Ilastik_Project_Channel_"+CellChan+".ilp";	
	File.mkdir(input + "4_Processed_Sections/Enhanced/"+CellChan);	
	EnOut = input + "4_Processed_Sections/Enhanced/"+CellChan+"/";
	File.mkdir(input + "4_Processed_Sections/Probability_Masks/"+CellChan);
	ProbOut = input + "4_Processed_Sections/Probability_Masks/"+CellChan+"/";
	if (ilastikmaskON == false) {
		MaskOut = 0;
		MaskThresh = 0;
	} else {
		File.mkdir(input + "4_Processed_Sections/Ilastik_Binary_Masks/"+CellChan);
		IlastikMasks = input + "4_Processed_Sections/Ilastik_Binary_Masks/"+CellChan+"/";
		MaskThresh = ilastikmaskthresh;
	}
	
	//process sections
	
	Sections = getFileList(dir);
	Sections = Array.sort(Sections);	

	ExistingProbs = getFileList(ProbOut);

	// check if aleady created
	
	if (ExistingProbs.length == Sections.length) {
		print("     Ilastik probability images already created. If you wish to recreate, delete directory: "+ProbOut+" ");
	} else {
		cleanupROI();
		
		ExistingEnhanced =  getFileList(EnOut);
		
		if (ExistingEnhanced.length == Sections.length) {
			print("     Enhanced images already created. If you wish to recreate, delete directory: "+EnOut+" ");
		
		} else {
			print("   Enhancing images for Ilastik segmentation...");
			run("Image Sequence...", "open=["+ dir + Sections[0] + "] scale=100 sort");
			getDimensions(Dwidth, Dheight, DChNum, Dslices, Dframes);
		
			if (BGSZ > 0) {
				run("Subtract Background...", "rolling="+ BGSZ + " stack");
			}
			run("Image Sequence... ", "format=TIFF save=["+EnOut+"Section0000.tif]");

			if (MaskOut != 0) {
				setThreshold(MaskThresh, 65535);
				setOption("BlackBackground", true);
				run("Convert to Mask", "method=Default background=Dark black");
				print(EnOut);
				print(MaskOut);
				run("Image Sequence... ", "format=PNG save=["+MaskOut+"Section0000.png]");
				
			}
			
			close();
			collectGarbage(Dslices, 4);
			print("  Complete.");
		}
	
		


		// Perform ilastik pixel classification
		
		//Ilastik Batch Processing
		ProjectCh = ClassDir + classifier;
		ProjectCh = replace(ProjectCh, "\\", "/");
		ProjectCh = q + ProjectCh + q;
	
		
		
		ProbOut = replace(ProbOut, "\\", "/");
		ProbOut = q + ProbOut + "{nickname}_Probabilities.tif" + q;
		ilcommandbatch = ilastik +" --headless --project="+ProjectCh+" --output_filename_format=" + ProbOut +" --raw_data ";
		EnOut2 = replace(EnOut, "\\", "/");
		MaskOut2 = replace(MaskOut, "\\", "/");

		
		EnSections = getFileList(EnOut);
		EnSections = Array.sort(EnSections);

		MaskSections = getFileList(MaskOut);
		MaskSections = Array.sort(MaskSections);
		
		print("Performing Ilastik pixel classification...");
		print("  Processing " + (EnSections.length) + " sections, please allow 10-30seconds / section.");

		for(i=0; i<EnSections.length; i++) {	
			EnSection = EnSections[i];
			
			if (MaskOut != 0) {
				MaskSection = MaskSections[i];
				NameFull = + q + EnOut2 + EnSection + q + " --prediction_mask " + q + MaskOut2 + MaskSection + q;
			} else {		
			 
				NameFull = EnOut2 + EnSection;
				NameFull = q + NameFull + q;
			
		
			ilcommandbatch = ilcommandbatch + NameFull +" ";
			}
		}

		run("Text Window...", "name=Batch");
		//print("[Batch]", "@echo off" + "\n");
		print("[Batch]", ilcommandbatch);
		run("Text...", "save=["+inputfixed +"/Ilastikrun.bat]");
		selectWindow("Ilastikrun.bat");
		run("Close"); 
		runilastik = input + "Ilastikrun.bat";
		runilastik = replace(runilastik, "\\", "/");
		runilastik = q + runilastik + q;
		exec(runilastik);
		
		results = getFileList(ProbOut);
		if (results.length < i) {
			wait(1000);
			results = getFileList(ProbOut);
			
		
			
		// add in validation creation image step, otherwise close
		//if(validation = true) {
				//open probability cell channel - expects cells REd Processes Green Background Blue
			//merge with enhanced
			//save in validation folder

		}

	}	

	print("  Complete.");
	DeleteFile(input+"Ilastikrun.bat");



}


function BGSubChannel(CellChan) {
	// e.g. BGSubChannel(CellDir3, Ch3EnhanceOut);
	//EnhanceAndFindMaxima(CellDir2, MaximaInt2, Ch2EnhanceOut, RegDir, CellCh2, Ch2ValOut);
	//process sections

	print("Processing channel "+CellChan+"...");
	if (File.exists(input + "4_Processed_Sections/Enhanced/"+CellChan)) {
			print("  Enhanced images already created.");
	} else {
	
	dir = RegDir+CellChan+"/";	
	File.mkdir(input + "4_Processed_Sections/Enhanced/"+CellChan);
	EnOut = input + "4_Processed_Sections/Enhanced/"+CellChan+"/";
	
	Sections = getFileList(dir);
	Sections = Array.sort(Sections);	

	
	cleanupROI();
	run("Image Sequence...", "open=["+ dir + Sections[0] + "] scale=100 sort");
	getDimensions(Dwidth, Dheight, DChNum, Dslices, Dframes);

	ExistingEnhanced =  getFileList(EnOut);
		
	if (ExistingEnhanced.length == Sections.length) {
		print("  Enhanced images already created. If you wish to recreate, delete directory: "+EnOut+" ");
	} else {
		print("  Enhancing images for projection density analysis...");

		if (BGSZ > 0){
			run("Subtract Background...", "rolling="+ BGSZ + " stack");
		}
		run("Image Sequence... ", "format=TIFF save=["+EnOut+"Section0000.tif]");
	}
	//close();
	collectGarbage(Dslices, 4);
	
  	close("*");
  	print("     Complete.");

}
}


function EnhanceAndFindMaxima(CellChan, MaximaInt) {
		// e.g 	EnhanceAndFindMaxima(CellDir3, MaximaInt3, Ch3EnhanceOut, RegDir, CellChan3, Ch3ValOut)
		//EnhanceAndFindMaxima(CellDir2, MaximaInt2, Ch2EnhanceOut, RegDir, CellCh2, Ch2ValOut);

	if (File.exists(input + "5_Analysis_Output/Cell_Analysis/C"+CellChan+"_Detected_Cells_Summary.csv")) {
		print("  Cell detection already performed. If you wish to rerun, delete directory: "+input + "5_Analysis_Output/Cell_Analysis/");
	} else {

		DeleteFile(CellCountOut + "Cell_Points_Ch"+CellChan+".csv");
		DeleteFile(CellIntensityOut + "Cell_Points_with_intensities_Ch"+CellChan+".csv");

		//process sections
		print("Preparing images for cell detection on channel: "+CellChan+"...");
		dir = RegDir+CellChan+"/";
		File.mkdir(input + "4_Processed_Sections/Enhanced/"+CellChan);
		EnOut = input + "4_Processed_Sections/Enhanced/"+CellChan+"/";
		File.mkdir(input + "4_Processed_Sections/Object_Detection_Validation/"+CellChan);
		ValOut = input + "4_Processed_Sections/Object_Detection_Validation/"+CellChan+"/";
		
		Sections = getFileList(dir);
		Sections = Array.sort(Sections);	
	
		cleanupROI();
		run("Image Sequence...", "open=["+ dir + Sections[0] + "] scale=100 sort");
		getDimensions(Dwidth, Dheight, DChNum, Dslices, Dframes);

		// check if images already enhanced
		ExistingEnhanced =  getFileList(EnOut);		
		if (ExistingEnhanced.length == Sections.length) {
			print("   Enhanced images already created. If you wish to recreate, delete directory: "+EnOut+" ");
		} else {
			print("   Enhancing images for Maxima detection...");
	
			if (BGSZ > 0){
				run("Subtract Background...", "rolling="+ BGSZ + " stack");
			}
			run("Image Sequence... ", "format=TIFF save=["+EnOut+"Section0000.tif]");
		}
		
		collectGarbage(Dslices, 4);
		rename("Stack");

		print("  Detecting cells...");
		// Find maxima only works on 1 image 
		MaximaSlices = nSlices();
	 	for (i=1; i<=MaximaSlices; i++) {
	    	selectImage("Stack");
	     	setSlice(i);
	     	run("Find Maxima...", "noise="+ MaximaInt +" output=[Single Points]");
	     	if (i==1)
	        	MaximaOutput = getImageID();
	    	else {
	      		run("Select All");
		       run("Copy");
		       close();
		       selectImage(MaximaOutput);
		       run("Add Slice");
		       run("Paste");
	   		 }
	 	}
		run("Select None");		
		close("Stack");
	
		selectImage(MaximaOutput);
		rename("Masks");
		//set values to 1 to ensure cooridinates are correct in resampling
		run("Properties...", "pixel_width=1 pixel_height=1 voxel_depth=1");
	
		//make sure headings aren't saved
		run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file");
	
		// measurement settings
		run("Set Measurements...", "centroid stack redirect=None decimal=3");
		
		run("Analyze Particles...", "display clear add stack");
	
	//Store cooridinates to readout later
		CountROI=roiManager("count"); 
		XCoordinate = newArray(CountROI);
		YCoordinate = newArray(CountROI);
		ZCoordinate = newArray(CountROI);
		MeasMeanInt1 = newArray(CountROI);
		MeasMeanInt2 = newArray(CountROI);
		MeasMeanInt3 = newArray(CountROI);
		MeasMeanInt4 = newArray(CountROI);
		for(j=0; j<CountROI; j++) {
			roiManager("Select", j);
			XCoordinate[j] = getValue("X");
			YCoordinate[j] = getValue("Y");
			ZCoordinate[j] = getValue("Slice");
		}
		run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file");
		saveAs("Results", CellCountOut + "Cell_Points_Ch"+CellChan+".csv");
		close("Results");
	
		// ROIS are populated, now measure on relevant channels and also create validation image
				// Measure intensities of all channels not AF and create validation images
		
		
		// situation can arise where user keeps ref chan at full res and performs cell analysis. In this case:
		// Let it import the channel and perform measurements
		if (FullResDAPI == true) {
			MeasureAlign = 100;
		} else {
			MeasureAlign = AlignCh;
		}
		
		
		print("  Measuring intensities and creating validation images...");
		ChNum = CountFolders(input+ "/3_Registered_Sections/");
				
		for(chl=1; chl<ChNum+1; chl++) {
			
			if (chl != MeasureAlign) {
	 			//open the stack
	 			RawSections = getFileList(RegDir + chl);
	 			RawSections = Array.sort( RawSections );
	 			Section1 = RawSections[0];
	 			run("Image Sequence...", "open=["+ RegDir + chl + "/" + Section1 + "] scale=100 sort");
	 			rename("RawStack");
	 			getDimensions(Drwidth, Drheight, DrChNum, Drslices, Drframes);
	 			run("Set Measurements...", "mean redirect=None decimal=3");

				MeasMeanInt = newArray(CountROI);
	 			// measure mean for each ROI
	 			print("     Measuring intensities for channel " + chl);
	 			for(n=0; n<CountROI;n++) { 
					roiManager("Select", n);
					MeasMeanInt[n] = getValue("Mean");					
				}
				
				if (chl == 1) { 
					MeasMeanInt1 = MeasMeanInt;
				}
				if (chl == 2) { 
					MeasMeanInt2 = MeasMeanInt;
				}
				if (chl == 3) { 
					MeasMeanInt3 = MeasMeanInt;
				}
				if (chl == 4) { 
					MeasMeanInt4 = MeasMeanInt;
				}

				// Create Validation Image
				if (chl == CellChan) {
						selectWindow("RawStack");
						rename("RawChStack");
				}
				
				// Create Intensity Validation Image
				if (chl == CellChan && IntVal == true) {
					newImage("Masks", "16-bit black", Drwidth, Drheight, Drslices);
					for(n=0; n<CountROI;n++) { 
						roiManager("Select", n);
						run("Add...", "value="+MeasMeanInt[n]+" slice");
					}
				}			
	 		}
		}
		close("RawStack");
			
		// Create and save Annotation Image
		cleanupROI();			
		print("   Creating cell detection validation image...");
		run("Merge Channels...", "c2=Masks c6=RawChStack");
		run("Scale...", "x=0.5 y=0.5 z=1.0 interpolation=None average create");
		run("16-bit");
		saveAs("Tiff", ValOut +"Cell_Detection_Validation.tif");
	
		close("Results");
		
		run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file save_column");
		

		////// Create a annotated table ////
		print("  Saving cell locations and measured intensities.");


		// Set a filename:
		CellFileOut = CellIntensityOut + "Cell_Points_with_intensities_Ch"+CellChan+".csv";
		
		// 1) Delete file if it exists - otherwise can produce error:
		if (File.exists(CellFileOut) ==1 ) {
			File.delete(CellFileOut);
		}
		
		// 2) Open file to write into
		WriteOut = File.open(CellFileOut);
		
		// 3) Print headings
		print(WriteOut, "X,Y,Z,Mean_Int_Ch1,Mean_Int_Ch2,Mean_Int_Ch3,Mean_Int_Ch4\n");

		// 4) Print lines
		for(j=0; j<CountROI; j++){ 
			print(WriteOut, XCoordinate[j]+","+YCoordinate[j]+","+ZCoordinate[j]+","+MeasMeanInt1[j]+","+MeasMeanInt2[j]+","+MeasMeanInt3[j]+","+MeasMeanInt4[j]);
		} 

		// 5) Close file
		File.close(WriteOut);
		
		close("Results"); 
	  	close("*");
	  	print("   Complete.");
	} 	
}

function detectcellsfromprob(CellChan, MinInt, cellsize) {

	print("Detecting cells for channel "+CellChan+" using Ilastik probability images...");

	if (File.exists(input + "5_Analysis_Output/Cell_Analysis/C"+CellChan+"_Detected_Cells_Summary.csv")) {
		print("     Cell detection already performed. If you wish to rerun, delete directory: "+input + "5_Analysis_Output/Cell_Analysis/");
	} else {

		DeleteFile(CellCountOut + "Cell_Points_Ch"+CellChan+".csv");
		DeleteFile(CellIntensityOut + "Cell_Points_with_intensities_Ch"+CellChan+".csv");
		
		ProbDir = input + "4_Processed_Sections/Probability_Masks/"+CellChan+"/";

		File.mkdir(input + "4_Processed_Sections/Object_Detection_Validation/"+CellChan);
		ValOut = input + "4_Processed_Sections/Object_Detection_Validation/"+CellChan+"/";
	
		
		masks = getFileList(ProbDir);
		masks = Array.sort( masks );
	
		if (masks.length == 0) {
			exit("Ilastik probability images not found. Please check the log. Is Ilastik running as expected?");
		}
		
		slice1 = masks[0];		
		run("Image Sequence...", "open=["+ ProbDir + slice1 + "] scale=100 sort");
		rename("Stack");
		run("Split Channels");
		close("Stack (blue)");
		close("Stack (green)");
		selectWindow("Stack (red)");
		//run("Duplicate...", "title=RawStack duplicate");
		//selectWindow("Stack (red)");
		rename("Stack");
	
		//REDIRECT TO ENHANCED IMAGE FOR VALIDATION - If option selected, otherwise delete VALIDATION folder
		
		//make sure headings aren't saved
		run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file");
		
		// measurement settings
		run("Set Measurements...", "centroid stack redirect=None decimal=3");
		// apply threshold
		setAutoThreshold("Default dark stack");
		setThreshold(MinInt, 255);
	
		setOption("BlackBackground", true);
		run("Convert to Mask", "method=Default background=Dark black");
		// watershed
		run("Watershed", "stack");
		// OPEN ROI MANAGER - bug in imagej if roi manager not open list can be empty? started april 2021
		run("ROI Manager...");
		//detect
		if (IntVal == true) {
			run("Analyze Particles...", "size=" +cellsize+ " circularity=0.1-1.00 clear add stack");
		} else {
			run("Analyze Particles...", "size=" +cellsize+ " circularity=0.1-1.00 show=Masks clear add stack");
			selectWindow("Mask of Stack");
			rename("Masks");
			//setBatchMode("Show");
		}
	
		//Store cooridinates to readout later
		CountROI=roiManager("count"); 
		XCoordinate = newArray(CountROI);
		YCoordinate = newArray(CountROI);
		ZCoordinate = newArray(CountROI);
		MeasMeanInt1 = newArray(CountROI);
		MeasMeanInt2 = newArray(CountROI);
		MeasMeanInt3 = newArray(CountROI);
		MeasMeanInt4 = newArray(CountROI);
		for(j=0; j<CountROI; j++) {
			roiManager("Select", j);
			XCoordinate[j] = getValue("X");
			YCoordinate[j] = getValue("Y");
			ZCoordinate[j] = getValue("Slice");
		}
		run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file");
		saveAs("Results", CellCountOut + "Cell_Points_Ch"+CellChan+".csv");
		close("Results");
	
		print("    Cell coordinates saved.");
	
		//selectWindow("Mask of Stacks");
		//run("Invert", "stack");
		
		// Measure intensities of all channels not AF and create validation images
		print("    Measuring intensities and creating validation images...");
	
		// situation can arise where user keeps ref chan at full res and performs cell analysis. In this case:
		// Let it import the channel and perform measurements
		if (FullResDAPI == true) {
			MeasureAlign = 100;
		} else {
			MeasureAlign = AlignCh;
		}

		ChNum = CountFolders(input+ "/3_Registered_Sections/");

		for(chl=1; chl<=ChNum; chl++) {
			
			if (chl != MeasureAlign) {
	 			//open the stack
	 			RawSections = getFileList(RegDir + chl);
	 			RawSections = Array.sort( RawSections );
	 			Section1 = RawSections[0];
	 			run("Image Sequence...", "open=["+ RegDir + chl + "/" + Section1 + "] scale=100 sort");
	 			rename("RawStack");
	 			getDimensions(Drwidth, Drheight, DrChNum, Drslices, Drframes);
	 			run("Set Measurements...", "mean redirect=None decimal=3");

				MeasMeanInt = newArray(CountROI);
	 			// measure mean for each ROI
	 			print("     Measuring intensities for channel " + chl);
	 			for(n=0; n<CountROI;n++) { 
					roiManager("Select", n);
					MeasMeanInt[n] = getValue("Mean");					
				}
				
				if (chl == 1) { 
					MeasMeanInt1 = MeasMeanInt;
				}
				if (chl == 2) { 
					MeasMeanInt2 = MeasMeanInt;
				}
				if (chl == 3) { 
					MeasMeanInt3 = MeasMeanInt;
				}
				if (chl == 4) { 
					MeasMeanInt4 = MeasMeanInt;
				}

				// Create Validation Image
				if (chl == CellChan) {
					selectWindow("RawStack");
					rename("RawChStack");
				}
				
				// Create Intensity Validation Image
				if (chl == CellChan && IntVal == true) {
					newImage("Masks", "16-bit black", Drwidth, Drheight, Drslices);
					for(n=0; n<CountROI;n++) { 
						roiManager("Select", n);
						run("Add...", "value="+MeasMeanInt[n]+" slice");
					}
				}		
			} 
			close("RawStack");	
		}

		cleanupROI();
		print("     Creating object detection validation image.");
		run("Merge Channels...", "c2=Masks c6=RawChStack");
		run("Scale...", "x=0.5 y=0.5 z=1.0 interpolation=None average create");
		run("16-bit");
		saveAs("Tiff", ValOut +"Cell_Detection_Validation.tif");
	
		close("Results");
		
		run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file save_column");
		
		////// Create a annotated table ////
		print("     Saving cell locations and measured intensities.");


		// Set a filename:
		CellFileOut = CellIntensityOut + "Cell_Points_with_intensities_Ch"+CellChan+".csv";
		
		// 1) Delete file if it exists - otherwise can produce error:
		if (File.exists(CellFileOut) ==1 ) {
			File.delete(CellFileOut);
		}
		
		// 2) Open file to write into
		WriteOut = File.open(CellFileOut);
		
		// 3) Print headings
		print(WriteOut, "X,Y,Z,Mean_Int_Ch1,Mean_Int_Ch2,Mean_Int_Ch3,Mean_Int_Ch4\n");

		// 4) Print lines
		for(j=0; j<CountROI; j++){ 
			print(WriteOut, XCoordinate[j]+","+YCoordinate[j]+","+ZCoordinate[j]+","+MeasMeanInt1[j]+","+MeasMeanInt2[j]+","+MeasMeanInt3[j]+","+MeasMeanInt4[j]);
		} 

	
		// 5) Close file
		File.close(WriteOut);
			
		print("     Complete.");
	  	close("*");
	  	close("Results");
	  	collectGarbage(10, 4);
	}
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

function E49TransPointsToXYZcsv(pathtofile, outputdir, filename) {
	filestring=File.openAsString(pathtofile); 
	//print(filestring);
	rows=split(filestring, "\n"); 
	//print("\\Clear");
	
	title1 = "Output_Points"; 
	title2 = "["+title1+"]"; 
	f=title2; 
	run("New... ", "name="+title2+" type=Table"); 
	print(f,"\\Headings:X\tY\tZ"); 
	
	//Get output point coordinates from the transformix output file
	for(i=0; i<rows.length; i++){ 
		columns=split(rows[i],";"); 
		OutputPoint=split(columns[4],"/ ");
		print(f,OutputPoint[3]+"\t"+OutputPoint[4]+"\t"+OutputPoint[5]);
	} 
	//Save this points to CSV
	
	selectWindow(title1);
	run("Text...", "save=["+ outputdir +"/"+filename+".csv]");
	//saveAs("Text", "["+ outputdir +"/"+filename+".csv]");
	selectWindow(title1);
	run("Close"); 
}
function E49TransPointsToZYXcsv(pathtofile, outputdir, filename) {
	filestring=File.openAsString(pathtofile); 
	rows=split(filestring, "\n"); 

	// Set a filename:
	CellFileOut = outputdir +"/"+filename+".csv";
	// 1) Delete file if it exists - otherwise can produce error:
	if (File.exists(CellFileOut) ==1 ) {
		File.delete(CellFileOut);
	}
	// 2) Open file to write into
	WriteOut = File.open(CellFileOut);

	// 3) Print headings
	print(WriteOut, "X,Y,Z\n");
	
	//Get output point coordinates from the transformix output file
	for(i=0; i<rows.length; i++){ 
		columns=split(rows[i],";"); 
		OutputPoint=split(columns[4],"/ ");
		// used to be sagittal so needed 5 4 3
		//print(f,OutputPoint[5]+"\t"+OutputPoint[4]+"\t"+OutputPoint[3]);
		//now coronal so 

		
// 4) Print lines
		print(WriteOut, OutputPoint[3]+","+OutputPoint[4]+","+OutputPoint[5]);
	} 
	// 5) Close file
	File.close(WriteOut);

}

function ResamplePoints() {
	TotalResults = nResults;
	//update to FIJI causing issues with headings - related to how csv file opened?
	// check results headings - if not C1 -C3 then:
	if (String.getResultsHeadings == "XYSlice") {
		Table.renameColumn("X", "C1");
		Table.renameColumn("Y", "C2");
		Table.renameColumn("Slice", "C3");
	} 
	
	for (i=0; i<TotalResults; i++) { 
		OriginalX = getResult("C1", i);
		setResult("C1", i, (parseInt(OriginalX*ResampleX)));
		OriginalY = getResult("C2", i);
		setResult("C2", i, (parseInt(OriginalY*ResampleY)));
		OriginalZ = getResult("C3", i);
		setResult("C3", i, (parseInt(OriginalZ*ResampleZ)));
	}
}


function ResamplePointsSC() {
	TotalResults = nResults;
	//update to FIJI causing issues with headings - related to how csv file opened?
	// check results headings - if not C1 -C3 then:
	if (String.getResultsHeadings == "XYSlice") {
		Table.renameColumn("X", "C1");
		Table.renameColumn("Y", "C2");
		Table.renameColumn("Slice", "C3");
	} 

	// Special Modification for spinal cord analysis - to stretch length to known length of isolated regions
	//Get the start and end slice based on the segment information provided
	SegmentCSV = File.openAsString(AtlasDir + "Segments.csv");
	SegmentCSVRows = split(SegmentCSV, "\n"); 
	for(i=0; i<SegmentCSVRows.length; i++){
		// Find Start Slice
		if(matches(SegmentCSVRows[i],".*"+SCSegRange[0]+".*") == 1 ){
			Row = split(SegmentCSVRows[i], ",");
			SCStartSlice = parseInt(Row[2])-1;
		}
		if(matches(SegmentCSVRows[i],".*"+SCSegRange[1]+".*") == 1 ){
			Row = split(SegmentCSVRows[i], ",");
			SCEndSlice = parseInt(Row[3]);
		}
	}
	SCTotalSlices = SCEndSlice-SCStartSlice;

	SCRawSlices = getFileList(input+ "/3_Registered_Sections/1/");	
	SCRawSlices = SCRawSlices.length;
	SCZCorrection = SCTotalSlices/SCRawSlices;
	
	for (i=0; i<TotalResults; i++) { 
		OriginalX = getResult("C1", i);
		setResult("C1", i, (parseInt(OriginalX*ResampleX)));
		OriginalY = getResult("C2", i);
		setResult("C2", i, (parseInt(OriginalY*ResampleY)));
		OriginalZ = getResult("C3", i);
		setResult("C3", i, (parseInt(OriginalZ*SCZCorrection)));
	}
}

function SwapColumnsXYZ_ZYX(TableTitle, f) {
	// Shift Point Orientation - for scanner XYZ should become ZYX

	run("New... ", "name="+TableTitle+" type=Table"); 
	print(f,"\\Headings:C1\tC2\tC3"); 
	for (i=0; i<TotalResults; i++) { 
		pasteX = getResult("C3", i);
		pasteY = getResult("C2", i);
		pasteZ = getResult("C1", i);
	
		print(f, pasteX+"\t"+pasteY+"\t"+pasteZ); 
	}
	
}

function CreateCellPoints(CellChan) {	
	if (File.exists(input + "5_Analysis_Output/Cell_Analysis/C"+CellChan+"_Cell_Points.tif")) {
		print("     Cell plots in template already performed. If you wish to rerun, delete : "+input + "5_Analysis_Output/Cell_Analysis/C"+CellChan+"_Cell_Points.tif");
	} else {

	celloutput = input + "5_Analysis_Output/Cell_Analysis/";
	
	run("Cell Point Creation", "select=["+input+"] select_0=["+celloutput+"] cell="+CellChan+" atlassizex="+AtlasSizeX+" atlassizey="+AtlasSizeY+" atlassizez="+AtlasSizeZ);

	print("   Cell points image creation complete.");
	}
}
	

function rawcoronalto3DsagittalDAPI (inputdir, outputdir, filename, outputres, BGround, ZCut) {
	// Creates a 3D sagittal brain from 2D coronal sections, requires BGround is min intensity, ZCut is section cut thickness
	// Use: 
	// rawcoronalto3Dsagittal(input+"/3_Registered_Sections/"+AlignCh, input+"/3_Registered_Sections", "Sagittal25DAPI", 25, BGround, ZCut);
	rawSections = getFileList(inputdir);
	rawSections = Array.sort( rawSections );
	Section1 = rawSections[0];

	open(inputdir + "/" + Section1);	
	getPixelSize(_, smW, _);
	close();

	scaledown = parseInt((smW/AtlasResXY)*100);

	//Note if scale <than 5 it won't import correctly so import at 5% and rescale as necessary OR import and then rescale

	if (scaledown < 5) {
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=5 sort");
		rename("DAPI");
		scaledown = ((scaledown * 20)/100);
		run("Scale...", "x="+scaledown+" y="+scaledown+" z=1.0 interpolation=Bilinear average process create title=DAPIsm");
		selectWindow("DAPI");
		close();
		selectWindow("DAPIsm");
	
	} else {
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale="+scaledown+" sort");
	}
	
	rename("DAPI");		
	run("Subtract...", "value="+BGround+" stack");
	run("Enhance Contrast...", "saturated=1 process_all use");
	//run("Median...", "radius=1 stack");
	if (List.get("Attenuation Correction")!="") {
		print("Correcting for intensity differences accross sections.");    
	    run("Attenuation Correction", "opening=3 reference=1");
	    close("DAPI");
	    close("Background of DAPI");
	    selectWindow("Correction of DAPI");
	    rename("DAPI");     
	}

	run("Properties...", "unit=micron voxel_depth="+ZCut+"");

	// Special Modification for spinal cord analysis - to stretch length to known length of isolated regions
	if (AtlasType == "Spinal Cord" && SCSegRange.length > 1) {
		//Get the start and end slice based on the segment information provided
		SegmentCSV = File.openAsString(AtlasDir + "Segments.csv");
		SegmentCSVRows = split(SegmentCSV, "\n"); 
		for(i=0; i<SegmentCSVRows.length; i++){
			// Find Start Slice
			if(matches(SegmentCSVRows[i],".*"+SCSegRange[0]+".*") == 1 ){
				Row = split(SegmentCSVRows[i], ",");
				SCStartSlice = parseInt(Row[2]);
			}
			if(matches(SegmentCSVRows[i],".*"+SCSegRange[1]+".*") == 1 ){
				Row = split(SegmentCSVRows[i], ",");
				SCEndSlice = parseInt(Row[3]);
			}
		}
		SCTotalSlices = SCEndSlice-SCStartSlice;
		SCRawSlices = nSlices;
		run("Reslice Z", "new="+ZCut*nSlices/SCTotalSlices);	
		print(" Registration dataset contains " + SCRawSlices + " slices. Segment range is " + SCSegRange[0] + " to  "+ SCSegRange[1] +", a total of "+ SCTotalSlices + " slices. Compensating to match.");
		
		
	} else {
		run("Reslice Z", "new="+AtlasResZ);
	}

	rename("Resliced");
	selectWindow("DAPI");
	close();
	selectWindow("Resliced");
	getPixelSize(aUnits, aWidth, aHeight);
	run("Properties...", "channels=1 unit=micron pixel_width="+parseInt(aWidth)+" pixel_height="+parseInt(aHeight)+" voxel_depth=25.0000");
	saveAs("Tiff", outputdir+"/"+filename+".tif");
	close();
	
}

function rawcoronalto3Dsagittal (inputdir, outputdir, filename, outputres, BGround, ZCut) {
	// Creates a 3D sagittal brain from 2D coronal slices, requires BGround is min intensity, ZCut is section cut thickness
	// Use: 
	// rawcoronalto3Dsagittal(input+"/3_Registered_Slices/"+AlignCh, input+"/3_Registered_Slices", "Sagittal25DAPI", 25, BGround, ZCut);
	rawSections = getFileList(inputdir);
	rawSections = Array.sort( rawSections );
	Section1 = rawSections[0];

	// import first slice to get resolution - alternatively - use CSV info file!
	
	open(inputdir + "/" + Section1);	
	getPixelSize(_, smW, _);
	close();
	//inputres = RegRes;
		
	scaledown = parseInt((smW/outputres)*100);

	//Note if scale <than 5 it won't import correctly so import at 5% and rescale as necessary OR import and then rescale

	if (scaledown < 5) {
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=5 sort");
		rename("DAPI");
		scaledown = ((scaledown * 20)/100);
		run("Scale...", "x="+scaledown+" y="+scaledown+" z=1.0 interpolation=Bilinear average process create title=DAPIsm");
		selectWindow("DAPI");
		close();
		selectWindow("DAPIsm");
	
	} else {
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale="+scaledown+" sort");
	}
	
	rename("DAPI");		
	selectWindow("DAPI");
	run("Subtract...", "value="+BGround+" stack");
	//run("Enhance Contrast...", "saturated=1 process_all use");
	//getDimensions(Dwidth, Dheight, DChNum, Dslices, Dframes);
	
	// Create DAPI/AF 25um dataset for atlas alignment
	//run("Median...", "radius=1 stack");

	//DAPIrescale = smW/25;
	//run("Scale...", "x="+DAPIrescale+" y="+DAPIrescale+" z=1.0 interpolation=Bilinear average process create title=DAPI25.tif");
	//selectWindow("DAPI");
	//close();
	//selectWindow("DAPI25.tif");
	setMinAndMax(0, 65535);
	run("Properties...", "unit=micron voxel_depth="+ZCut+"");
	//run("Reslice [/]...", "output=25 start=Left rotate");
	//selectWindow("DAPI25.tif");
	//selectWindow("DAPI");
	//close();
	//selectWindow("Reslice of DAPI");
	getPixelSize(aUnits, aWidth, aHeight);
	run("Properties...", "channels=1 unit=micron pixel_width="+parseInt(aWidth)+" pixel_height="+parseInt(aHeight)+" voxel_depth=25.0000");
	saveAs("Tiff", outputdir+"/"+filename+".tif");
	close();
	
}

function enhancedcoronalto3Dsagittalbinary (inputdir, outputdir, filename, outputres, ProBGround, ZCut) {
	// Creates a 3D sagittal brain from 2D coronal sections, requires BGround is min intensity, ZCut is section cut thickness
	// Use: 
	// rawcoronalto3Dsagittal(input+"/3_Registered_Sections/"+AlignCh, input+"/3_Registered_Sections", "Sagittal25DAPI", 25, BGround, ZCut, ProBGSub);
	//(input+"/3_Registered_Slices/"+CellCh, input+"/3_Registered_Sections", "Sagittal25_C1_Binary", 25, ProChBG, ZCut)
	if (File.exists(inputdir) == 1) { 
		rawSections = getFileList(inputdir);
		rawSections = Array.sort( rawSections );
		Section1 = rawSections[0];
		//setBatchMode(false);
		// import first section to get resolution - alternatively - use CSV info file!
	
		open(inputdir + "/" + Section1);	
		getPixelSize(_, smW, _);
		close();
		//inputres = RegRes;
		
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=100 sort");
		
		setAutoThreshold("Default dark stack");
		setThreshold(ProBGround, 65535);
		run("Convert to Mask", "method=Default background=Dark black");
		Original = getImageID();
	
		run("Properties...", "unit=micron voxel_depth="+ZCut+"");
	
		scaledown = smW/outputres;
		scaleZ = ZCut/ProAnResSection;
			
		//run("Scale...", "x="+scaledown+" y="+scaledown+" z="+scaleZ+" interpolation=Bilinear average process create");
		run("Scale...", "x="+scaledown+" y="+scaledown+" z="+scaleZ+" interpolation=None process create");

	
		SCALE = getImageID();
		
		selectImage(Original);
		close();
		run("Properties...", "unit=micron pixel_width="+outputres+" pixel_height="+outputres+" voxel_depth="+ProAnResSection+"");	
		setMinAndMax(0, 65535);
		//ResliceSagittalCoronal();
		rename("DAPI");		
		resetMinAndMax();
		//convert to binary image - or create a modified function of above that only saves the binary
		//print(ProBGround);
		setAutoThreshold("Default dark stack");
		setThreshold(10, 256);
		run("Convert to Mask", "method=Default background=Dark black");
		getPixelSize(aUnits, aWidth, aHeight);
		run("Properties...", "channels=1 unit=micron pixel_width="+parseInt(aWidth)+" pixel_height="+parseInt(aHeight)+" voxel_depth=25.0000");
		saveAs("Tiff", outputdir+"/"+filename+".tif");
		close();
	} else {
		print("Directory ("++") does not exist, skipping this analysis, check settings.");
	}
	
}

function coronalto3Dsagittal (inputdir, outputdir, filename, outputres, ZCut) {
	// Creates a 3D sagittal brain from 2D coronal Sections, requires BGround is min intensity, ZCut is section cut thickness
	// Use: 
	// coronalto3Dsagittal(input+"/3_Registered_Sections/"+AlignCh, input+"/3_Registered_Sections", "Sagittal25DAPI", 25, BGround, ZCut, ProBGSub);
	//(input+"/3_Registered_Sections/"+CellCh, input+"/3_Registered_Sections", "Sagittal25_C1_Binary", 25, ProChBG, ZCut)
	if (File.exists(outputdir+"/"+filename+".tif") == 0) {
			
		rawSections = getFileList(inputdir);
		rawSections = Array.sort( rawSections );
		Section1 = rawSections[0];
		
		open(inputdir + "/" + Section1);	
		getPixelSize(_, smW, _);
		close();
		
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=100 sort");
		Original = getImageID();
		
		run("Properties...", "unit=micron voxel_depth="+ZCut+"");
		
		scaledown = smW/outputres;
		scaleZ = ZCut/ProAnResSection;
				
		run("Scale...", "x="+scaledown+" y="+scaledown+" z="+scaleZ+" interpolation=Bilinear average process create");
		SCALE = getImageID();
		
		selectImage(Original);
		close();
		run("Properties...", "unit=micron voxel_depth="+ZCut+"");	
		setMinAndMax(0, 65535);
		//ResliceSagittalCoronal();
		rename("DAPI");		
		resetMinAndMax();
		getPixelSize(aUnits, aWidth, aHeight);
		run("Properties...", "channels=1 unit=micron pixel_width="+parseInt(aWidth)+" pixel_height="+parseInt(aHeight)+" voxel_depth=25.0000");
		saveAs("Tiff", outputdir+"/"+filename+".tif");
		close();
	} else {
		print("  Already created.");
	}
	
}


function closewindow(windowname) {
	if (isOpen(windowname)) { 
      		 selectWindow(windowname); 
       		run("Close"); 
  		} 
}


function AnnotatePoints (PointsIn, AtlasAnnotationImg, AtlasAnnotationCSV, MeasuredIntCSV, AnnotatedSummary, AnnotatedOut) {
	run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file save_column");
	run("Set Measurements...", "mean redirect=None decimal=3");
	setTool("point");
	OpenAsHiddenResults(PointsIn);
	ChCount = nResults;
	open(AtlasAnnotationImg);
	rename("annotation");
	XPos = newArray(nResults);
	YPos = newArray(nResults);
	ZPos = newArray(nResults);
	Z_Dither = newArray(nResults);
	//Create Mean Measurement Array
	MeanMeasurements = newArray(nResults);
	HemisphereArray = newArray(nResults);
	
	for (i = 0; i < ChCount; i++) {
		X = getResult("X", i);
		XPos[i] = X;
		Y = getResult("Y", i);
		YPos[i] = Y;
		Z = getResult("Z", i);
		ZPos[i] = Z;
		// Dither Z to reduce clustering in cases where sectioning is larger than Z resolutio - for display only
		
		if (ZCut>AtlasResZ) {
			Uncertainty = ZCut/AtlasResZ;
			Z=Z-Uncertainty/2;
			Randomizer = Uncertainty * random;
			Z = Z + Randomizer;
		
		}
		if (Z < 1) {
			Z = 1;
		}

		Z_Dither[i] = Z;
		
		selectWindow("annotation");
		if (Z <= AtlasSizeZ) {
			setSlice(Z);
			makePoint(X, Y);
			MeanMeasurements[i] = getValue("Mean");
		} else {
			CellPlotCheck = CellPlotCheck + 1;
		}
	}

	close("Results");
	
	//import measured intensities and add them to the Detected Cells output
	OpenAsHiddenResults(MeasuredIntCSV);
	ChCount2 = nResults;
	MeanIntCh1 = newArray(nResults);
	MeanIntCh2 = newArray(nResults);
	MeanIntCh3 = newArray(nResults);
	MeanIntCh4 = newArray(nResults);
	for (i = 0; i < ChCount2; i++) {
		MeanIntCh1[i] = getResult("Mean_Int_Ch1", i);
		MeanIntCh2[i] = getResult("Mean_Int_Ch2", i);
		MeanIntCh3[i] = getResult("Mean_Int_Ch3", i);
		MeanIntCh4[i] = getResult("Mean_Int_Ch4", i);
	}
	
	close("Results");
	
	//Import Regions and create Array for ID and Names
	OpenAsHiddenResults(AtlasAnnotationCSV);
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

	//Create a annotated table -- update later to include region names

	// Set a filename:
	CellFileOut = AnnotatedOut;
	
	// 1) Delete file if it exists - otherwise can produce error:
	if (File.exists(CellFileOut) ==1 ) {
		File.delete(CellFileOut);
	}
	// 2) Open file to write into
	WriteOut = File.open(CellFileOut);
	// 3) Print headings
	print(WriteOut, "X,Y,Z,Z_Dither,Bregma_AP,Bregma_DV,Bregma_ML,Mean_Int_Ch1,Mean_Int_Ch2,Mean_Int_Ch3,Mean_Int_Ch4,Hemisphere,ID,Acronym\n");
	//print(WriteOut, "X,Y,Z,Z_Dither,Mean_Int_Ch1,Mean_Int_Ch2,Mean_Int_Ch3,Mean_Int_Ch4,Hemisphere,ID\n");

	
	for(i=0; i<ChCount; i++){ 
	
		if (XPos[i] <= AtlasSizeX/2) {
			HemisphereArray[i] = "Right";
			
		} else {
			HemisphereArray[i] = "Left";
		}
		BregmaAP = ((ZPos[i]*25)-5350)*-1;
		BregmaDV = ((YPos[i]*25)-470)*-1;
		BregmaML = XPos[i]*25-5700;

		// Update Region Intensity to Reflect OutputIDs
		location = LocateID(RegionIDs, MeanMeasurements[i]);
		trueID = OutputRegionIDs[location];
		trueAcr = RegionAcr[location]; 
		// Look up Acronym based on OutputID
		
		
		//print(WriteOut, XPos[i]+","+YPos[i]+","+ZPos[i]+","+Z_Dither[i]+","+BregmaAP+","+BregmaDV+","+BregmaML+","+MeanIntCh1[i]+","+MeanIntCh2[i]+","+MeanIntCh3[i]+","+MeanIntCh4[i]+","+HemisphereArray[i]+","+MeanMeasurements[i]);
		
		print(WriteOut, XPos[i]+","+YPos[i]+","+ZPos[i]+","+Z_Dither[i]+","+BregmaAP+","+BregmaDV+","+BregmaML+","+MeanIntCh1[i]+","+MeanIntCh2[i]+","+MeanIntCh3[i]+","+MeanIntCh4[i]+","+HemisphereArray[i]+","+trueID+","+trueAcr);
	} 

	// 5) Close file
	File.close(WriteOut);
	
	// Then do region counts
	RegionCountsLeft = newArray(NumIDs);
	RegionCountsRight = newArray(NumIDs);
	for (i=0; i<RegionIDs.length; i++) {
		ID = RegionIDs[i];
		LeftCount = 0;
		RightCount = 0;
		for(j = 0; j< MeanMeasurements.length; ++j){
	   		if(MeanMeasurements[j] == ID && HemisphereArray[j] == "Left") {
	   			LeftCount = LeftCount+1;
	   		}
	   		if(MeanMeasurements[j] == ID && HemisphereArray[j] == "Right") {
	   			RightCount = RightCount+1;
	   		}
	   		
		}
		RegionCountsLeft[i] = LeftCount;
		RegionCountsRight[i] = RightCount;
	}
		
	//put region counts into table.

	// Set a filename:
	CellFileOut = AnnotatedSummary;
		
	// 1) Delete file if it exists - otherwise can produce error:
	if (File.exists(CellFileOut) ==1 ) {
		File.delete(CellFileOut);
	}
		
	// 2) Open file to write into
	WriteOut = File.open(CellFileOut);
		
	// 3) Print headings
	print(WriteOut,"Total_Cells_Right,Total_Cells_Left,ID,Acronym,Name,Graph_Order,Parent_ID,Parent_Acronym,Graph_ID_Path"); 

	if (Modified_IDs == "true") {
		RegionIDs = OutputRegionIDs;
	}
	for(i=0; i<RegionNames.length; i++){ 
		print(WriteOut, RegionCountsRight[i]+","+RegionCountsLeft[i]+","+RegionIDs[i]+","+RegionAcr[i]+",\""+RegionNames[i]+"\","+Graph_Order[i]+","+ParentIDs[i]+",\""+ParentNames[i]+"\",\""+Graph_Path[i]+"\"");
	} 

	// 5) Close file
	File.close(WriteOut);

}	


function createColorProjections(Channel) {

// example of use:
// createColorProjections(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv", ProCh, input + "5_Analysis_Output/Temp/Transformed_C"+ProCh+"_Binary_Out/result.mhd", input+"/5_Analysis_Output");
// createColorProjections(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv", ProCh, input + "5_Analysis_Output/Temp/Transformed_C"+ProCh+"_Binary_Out/result.mhd", input+"/5_Analysis_Output");
	print("Creating projection density images for channel "+Channel);
	
	if (File.exists(TransformedProjectionDataOut + "C"+Channel+"_Atlas_Colored_Projections.tif")) {
		print("     Projection density heatmap already created. If you wish to rerun, delete: \n     "+TransformedProjectionDataOut + "C"+Channel+"_Atlas_Colored_Projections.tif");
	} else {

	
	open(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/OriginPoints.csv");
	Table.rename(Table.title, "Results");
	IndexOrigin=parseInt(getResult("Z", 0));
	IndexEnd=parseInt(getResult("Z", 1));
	close("Results");

	if (File.exists(TransformedProjectionDataOut + "C"+Channel+"_binary_projection_data_in_atlas_space.tif")) {
 
		open(TransformedProjectionDataOut + "C"+Channel+"_binary_projection_data_in_atlas_space.tif");
	
		rename("ExpProjections");
	
		run("Divide...", "value=255 stack");
			
		run("Duplicate...", "title=ExpProjections-Part2 duplicate");
		run("Duplicate...", "title=ExpProjections-Part3 duplicate");
		run("Merge Channels...", "c1=ExpProjections c2=ExpProjections-Part2 c3=ExpProjections-Part3 create");
		rename("ExpProjections");
		
		// import atlas
		open(AtlasDir + "Annotation_Color.tif");
		rename("ColorAnnotations");
			
			
		imageCalculator("Multiply create stack", "ExpProjections","ColorAnnotations");
		close("ExpProjections");
		close("ColorAnnotations");
		selectWindow("Result of ExpProjections");
		Stack.setChannel(1)
		setMinAndMax(0, 255);
		Stack.setChannel(2)
		setMinAndMax(0, 255);
		Stack.setChannel(3)
		setMinAndMax(0, 255);
		run("8-bit");
		run("RGB Color", "slices");
		if (OutputType == "Sagittal") {
			ResliceSagittalCoronal();
		}
		saveAs("Tiff", TransformedProjectionDataOut + "C"+Channel+"_Atlas_Colored_Projections.tif");
		
		close();
		//close("Colored_Projections"+Channel+".tif");
		} else {
			VisRegCheck = 1;
		}
	}
//return VisRegCheck;

}

function OverlayColorProjectionsOnTemplate(Projections, Channel, OutputDir) {

// example of use:
// OverlayColorProjectionsOnTemplate(input + "5_Analysis_Output/Colored_Projections_C"+ProCh+".tif", ProCh, input+"/5_Analysis_Output");

	print("Creating projections overlayed with template and 3D images for channel "+Channel);

	if (File.exists(OutputDir + "/C"+Channel+"_Atlas_Colored_Projections_Templated_Overlay_3D.tif")) {
		print("     3D projection images already created. If you wish to rerun, delete: \n     "+OutputDir + "/C"+Channel+"_Atlas_Colored_Projections_Templated_Overlay_3D.tif");
	} else {

		
	// import atlas
	open(AtlasDir + "Template.tif");
	if (OutputType == "Sagittal") {
		ResliceSagittalCoronal();
	}
	rename("Template");
	setMinAndMax(0, 600);
	run("8-bit");



	//import projections
	open(Projections);	
	rename("Projections");
	//setMinAndMax(0, 185);
	run("Apply LUT", "stack");
	//run("Gaussian Blur 3D...", "x=1 y=1 z=1");
	//run("Enhance Contrast", "saturated=0.35");
	run("Split Channels");

	//Do image calculations
	imageCalculator("Subtract create stack", "Template","Projections (red)");
	imageCalculator("Add stack", "Result of Template","Projections (red)");
	selectWindow("Result of Template");
	rename("Red");
	close("Projections (red)");

	imageCalculator("Subtract create stack", "Template","Projections (green)");
	imageCalculator("Add stack", "Result of Template","Projections (green)");
	selectWindow("Result of Template");
	rename("Green");
	close("Projections (green)");

	imageCalculator("Subtract create stack", "Template","Projections (blue)");
	imageCalculator("Add stack", "Result of Template","Projections (blue)");
	selectWindow("Result of Template");
	rename("Blue");
	close("Projections (blue)");
	
	close("Template");
	

	run("Merge Channels...", "c1=Red c2=Green c3=Blue create");

	saveAs("Tiff", OutputDir + "/C"+Channel+"_Atlas_Colored_Projections_Templated_Overlay.tif");
	run("3D Project...", "projection=[Brightest Point] axis=Y-Axis slice=25 initial=0 total=360 rotation=10 lower=1 upper=255 opacity=0 surface=100 interior=50");
	saveAs("Tiff", OutputDir + "/C"+Channel+"_Atlas_Colored_Projections_Templated_Overlay_3D.tif");
	close("C"+Channel+"_Atlas_Colored_Projections_Templated_Overlay.tif");
	close("C"+Channel+"_Atlas_Colored_Projections_Templated_Overlay_3D.tif");
	close("*");
	collectGarbage(10, 4);
	print("  Complete.");
	}


}
 	

function MeasureIntensitiesLRHemisphereFullRes(Channel) {
	// Previously: (OriginPoints, Channel, TransformedInputImage, OutputDir)
	// (input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv", j, TransformedRawDataOut+"/"+"C"+j+"_raw_data_in_atlas_space.tif", input+"/5_Analysis_Output/Region_Mean_Intensity_Measurements")
	
	// creates a volume and density table when given binary projections
		
	IntOutputDir = input+"/5_Analysis_Output/Region_Mean_Intensity_Measurements_XY_"+ProAnRes+"_Z_"+ZCut+"micron/";

	if (File.exists(IntOutputDir+"C"+Channel+"_Measured_Region_Intensity.csv")) {
			print("     Intensity heatmap already created. If you wish to rerun, delete : \n     "+IntOutputDir+"C"+Channel+"_Measured_Region_Intensity.csv");
	} else {
	
		if (File.exists(IntOutputDir) == 0) {
			File.mkdir(IntOutputDir);
		}
	
		print("   Importing registered raw data for intensity measurements...");
		
		inputdir = RegDir+Channel;
		rawSections = getFileList(inputdir);
		rawSections = Array.sort( rawSections );
		Section1 = rawSections[0];
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=100 sort");
		run("Properties...", "unit=micron voxel_depth="+ZCut+"");
	
		// Rescale if necessary 
		if (ProAnRes < FinalRes) {
			ProAnRes = FinalRes;
		}
		scaledown = FinalRes/ProAnRes;
		scaleZ = 1;
		run("Scale...", "x="+scaledown+" y="+scaledown+" z="+scaleZ+" interpolation=None process create");
		rename("RawIntensityData");
		getDimensions(IMwidth, IMheight, channels, IMslices, frames);
		
		close("\\Others");
	
		
		// Import Annotations
	
		print("   Importing and scaling annotation data for analysis...");
		
		open(input + "5_Analysis_Output/Transformed_Annotations.tif");
		rename("Annotations");
		run("Size...", "width="+IMwidth+" height="+IMheight+" depth="+IMslices+" interpolation=None");
		
		// Import Hemisphere Mask
		open(input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif");
		rename("Hemi_Annotations");
		run("Size...", "width="+IMwidth+" height="+IMheight+" depth="+IMslices+" interpolation=None");
		run("Divide...", "value=255 stack");
	
		// Open annotation table		
		OpenAsHiddenResults(AtlasDir + "Atlas_Regions.csv");
		NumIDs = (nResults);
		RegionIDs = newArray(NumIDs);
		RegionNames = newArray(NumIDs);
		RegionAcr = newArray(NumIDs);
		ParentIDs = newArray(NumIDs);
		ParentNames = newArray(NumIDs);
		Graph_Order = newArray(NumIDs);
		Graph_Path = newArray(NumIDs);
		if (Modified_IDs == "true") {
			OutputRegionIDs = newArray(NumIDs);
		}
		for(i=0; i<NumIDs; i++) {
			RegionIDs[i] = getResult("id", i);
			RegionNames[i] = getResultString("name", i);	
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
			print("   Annotated volumes already measured.");
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
			print("   Measurements complete.");

		}		

		print("   Measuring intensities in annotated regions...");
		
		ExpIntensityLeft = newArray(NumIDs);
		ExpIntensityRight = newArray(NumIDs);
			
		for (j=0; j<NumIDs; j++) {
			// template > isolate region > multipy with Exp brain > conv 32bit > Sum left and right hemispheres > Measure
			
			selectWindow("Annotations");
			run("Duplicate...", "title=Annotations-Sub duplicate");
			selectWindow("Annotations-Sub");
			setThreshold(RegionIDs[j], RegionIDs[j]);
			run("Convert to Mask", "method=Default background=Dark black");
			run("Clear Results");
			//divide by 255 to get binary
			run("Divide...", "value=255 stack");
	
			//Measure for Right side
			imageCalculator("Multiply create stack", "Annotations-Sub","Hemi_Annotations");
			selectWindow("Result of Annotations-Sub");
			imageCalculator("Multiply create stack", "RawIntensityData","Result of Annotations-Sub");
			close("Result of Annotations-Sub");
			selectWindow("Result of RawIntensityData");
			rename("RT");
			run("32-bit");	
			run("Z Project...", "projection=[Sum Slices]");
			close("RT");
			selectWindow("SUM_RT");
			getRawStatistics(n, mean, min, max, std, hist); 
			getDimensions(anWidth, anHeight, _, _, _);
			ExpIntensityRight[j] = (mean*anWidth*anHeight);
			close("SUM_RT");	
	
			//Measure for Left side
			imageCalculator("Subtract create stack", "Annotations-Sub","Hemi_Annotations");
			selectWindow("Result of Annotations-Sub");
			imageCalculator("Multiply create stack", "RawIntensityData","Result of Annotations-Sub");
			close("Result of Annotations-Sub");
			selectWindow("Result of RawIntensityData");
			rename("RT");
			run("32-bit");	
			run("Z Project...", "projection=[Sum Slices]");
			close("RT");
			selectWindow("SUM_RT");
			getRawStatistics(n, mean, min, max, std, hist); 
			getDimensions(anWidth, anHeight, _, _, _);
			ExpIntensityLeft[j] = (mean*anWidth*anHeight);
			close("SUM_RT");	
	
			close("Annotations-Sub");
		}	
		close("Annotations");
		//put intensity measurements into table.. do we need any other columns?
		title1 = "Annotated_Volumes"; 
		title2 = "["+title1+"]"; 
		f=title2; 
		run("New... ", "name="+title2+" type=Table"); 
		print(f,"\\Headings:Region_Volume_Right\tRegion_Volume_Left\tTotal_Intensity_Right\tTotal_Intensity_Left\tMean_Intensity_Right\tMean_Intensity_Left\tID\tAcronym\tName\tGraph_Order\tParent_ID\tParent_Acronym\tGraph_ID_Path"); 
		
		//print(f,"\\Headings:Count\tRegion_ID\tName\tAcronym\tParent_Acronym"); 
		// print each line into table 
		open(AtlasDir + "Atlas_Regions.csv");
		Table.rename(Table.title, "Results");

		if (Modified_IDs == "true") {
			RegionIDs = OutputRegionIDs;
		}
		
		for(i=0; i<RegionNames.length; i++){ 
			
			MeanIntensityLeft = (ExpIntensityLeft[i]/VolumesLeft[i]);
			MeanIntensityRight = (ExpIntensityRight[i]/VolumesRight[i]);
			
			if (isNaN(MeanIntensityLeft) == 1) {
				MeanIntensityLeft = 0;
			}
			if (isNaN(MeanIntensityRight) == 1) {
				MeanIntensityRight = 0;
			}

			print(f,VolumesRight[i]+"\t"+VolumesLeft[i]+"\t"+ExpIntensityRight[i]+"\t"+ExpIntensityLeft[i]+"\t"+MeanIntensityRight+"\t"+MeanIntensityLeft+"\t"+RegionIDs[i]+","+RegionAcr[i]+",\""+RegionNames[i]+"\","+Graph_Order[i]+","+ParentIDs[i]+",\""+ParentNames[i]+"\",\""+Graph_Path[i]+"\""
);
		} 
		close("Results");
		selectWindow(title1);
		//Find way of renaming table to results so that it can be edited as results. For NOW just save and reopen
		//IJ.renameResults(title1,"Results");
		run("Text...", "save=["+ IntOutputDir+"C"+Channel+"_Measured_Region_Intensity.csv]");
	
		close(title1);
	
		close("*");
		collectGarbage(10, 4);	
		
		print("   Intensity measurements complete.");
	}
		
}


function createColorCells(Channel, BinaryCells, OutputDir) {

// example of use:
// createColorCells(CellCh, input + "5_Analysis_Output/Cell_Points_C1.tif", input+"/5_Analysis_Output");

	if (File.exists(input + "5_Analysis_Output/Cell_Analysis/C"+Channel+"_Atlas_Colored_Cells.tif")) {
		print("     Color cell plotting already performed. If you wish to rerun, delete : "+input + "5_Analysis_Output/Cell_Analysis/C"+Channel+"_Atlas_Colored_Cells.tif");
	} else {
	
	open(BinaryCells);
	
	if (OutputType == "Sagittal") {
		ResliceSagittalCoronal();
	}
	
	rename("ExpCells");
		//crop out density analysis region - currently using -5 to be conservative, potentially use better origin points
		
	run("Divide...", "value=255 stack");
	run("Duplicate...", "title=ExpCells-Part2 duplicate");
	run("Duplicate...", "title=ExpCells-Part3 duplicate");

	run("Merge Channels...", "c1=ExpCells c2=ExpCells-Part2 c3=ExpCells-Part3 create");
	rename("ExpCells");
	
	// import atlas
	open(AtlasDir + "Annotation_Color.tif");
	rename("ColorAnnotations");
		
		
	imageCalculator("Multiply create stack", "ExpCells","ColorAnnotations");
	close("ExpCells");
	close("ColorAnnotations");
	selectWindow("Result of ExpCells");
	Stack.setChannel(1)
	setMinAndMax(0, 255);
	Stack.setChannel(2)
	setMinAndMax(0, 255);
	Stack.setChannel(3)
	setMinAndMax(0, 255);
	run("8-bit");
	run("RGB Color", "slices");
	if (OutputType == "Sagittal") {
		ResliceSagittalCoronal();
	}
	saveAs("Tiff", OutputDir + "/C"+Channel+"_Atlas_Colored_Cells.tif");
	close();
	//close("Colored_Projections"+Channel+".tif");
	}

}

function OverlayColorCellsOnTemplate(Cells, Channel, OutputDir) {

// example of use:
// OverlayColorCellsOnTemplate(input + "5_Analysis_Output/Colored_Cells_C"+CellCh+".tif", CellCh, input+"/5_Analysis_Output");
	if (File.exists(input + "5_Analysis_Output/Cell_Analysis/C"+Channel+"_Atlas_Colored_Cells_Template_Overlay.tif")) {
		print("     Cell plotting already performed. If you wish to rerun, delete : "+input + "5_Analysis_Output/Cell_Analysis/C"+Channel+"_Atlas_Colored_Cells_Template_Overlay.tif");
	} else {


		
	// import atlas
	open(AtlasDir + "Template.tif");
	if (OutputType == "Sagittal") {
		ResliceSagittalCoronal();
	}
	rename("Template");
	setMinAndMax(0, 600);
	run("8-bit");

	//import projections
	open(Cells);	
	rename("Cells");
	run("Split Channels");

	//Do image calculations
	imageCalculator("Subtract create stack", "Template","Cells (red)");
	imageCalculator("Add stack", "Result of Template","Cells (red)");
	selectWindow("Result of Template");
	rename("Red");
	close("Cells (red)");

	imageCalculator("Subtract create stack", "Template","Cells (green)");
	imageCalculator("Add stack", "Result of Template","Cells (green)");
	selectWindow("Result of Template");
	rename("Green");
	close("Cells (green)");

	imageCalculator("Subtract create stack", "Template","Cells (blue)");
	imageCalculator("Add stack", "Result of Template","Cells (blue)");
	selectWindow("Result of Template");
	rename("Blue");
	close("Cells (blue)");
	
	close("Template");
	

	run("Merge Channels...", "c1=Red c2=Green c3=Blue create");

	run("Properties...", "pixel_width=25.0000 pixel_height=25.0000 voxel_depth=25.0000");
	saveAs("Tiff", OutputDir + "/C"+Channel+"_Atlas_Colored_Cells_Template_Overlay.tif");
	
	if (AtlasType != "Spinal Cord") {
		run("3D Project...", "projection=[Brightest Point] axis=Y-Axis slice=25 initial=0 total=360 rotation=10 lower=1 upper=255 opacity=0 surface=100 interior=50");
		saveAs("Tiff", OutputDir + "/C"+Channel+"_Atlas_Colored_Cells_Template_Overlay_3D.tif");
		close("C"+Channel+"_Atlas_Colored_Cells_Template_Overlay_3D.tif");
	}
	close("C"+Channel+"_Atlas_Colored_Cells_Template_Overlay.tif");
	close("*");
	}
}

function CreateABADensityHeatmapJS(Chan) {
	print(" Creating density heatmap for channel "+Chan);
	ProjectionDensityOut = AlignDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron";

	if (File.exists(ProjectionDensityOut + "/C"+Chan+"_Region_Density_Heatmap.tif")) {
		print("     Projection density heatmap already created. If you wish to rerun, delete: \n     "+ProjectionDensityOut + "/C"+Chan+"_Region_Density_Heatmap.tif");
	} else {
			
		run("Region Density Heatmap Creation", "select=["+input+"] select_0=["+ProjectionDensityOut+"] select_1=["+AtlasDir+"] cell="+Chan+" atlassizex="+AtlasSizeX+" atlassizey="+AtlasSizeY+" atlassizez="+AtlasSizeZ);
		open(ProjectionDensityOut + "/C"+Chan+"_Region_Density_Heatmap.tif");
		ResliceSagittalCoronal();	
		saveAs("Tiff", ProjectionDensityOut + "/C"+Chan+"_Region_Density_Heatmap.tif");
		close("*");
		collectGarbage(10, 4);
		print("     Complete.");
	}
}

 		
function CreateABADensityHeatmap(Chan) {			
		
	//get origin front and back
	print(" Creating density heatmap for channel "+Chan);

	if (File.exists(AlignDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Chan+"_Atlas_Density_Heatmap.tif")) {
		print("     Projection density heatmap already created. If you wish to rerun, delete: \n     "+AlignDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Chan+"_Atlas_Density_Heatmap.tif");
	} else {

	open(AlignDir+"/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Chan+"_Measured_Projection_Density.csv");
	Table.rename(Table.title, "Results");
	NumIDs = (nResults);
	RegionIDs = newArray(NumIDs);
	RegionDensityLeft = newArray(NumIDs);
	RegionDensityRight = newArray(NumIDs);
	for(NumIDcount=0; NumIDcount<NumIDs; NumIDcount++) {
		RegionIDs[NumIDcount] = getResult("ID", NumIDcount);
		RegionDensityLeft[NumIDcount] = getResultString("Projection_Density_Left", NumIDcount);
		RegionDensityRight[NumIDcount] = getResultString("Projection_Density_Right", NumIDcount);
	}
	close("Results");	
	
	//create empty heatmap image (these are just 8bit for now so scale is % but could be 16bit for decimal places
	newImage("Heatmap", "8-bit black", AtlasSizeX, AtlasSizeY, AtlasSizeZ);
	ResliceSagittalCoronal();
	rename("Heatmap");
	
	//process each region
	for(NumIDcount=0; NumIDcount<NumIDs; NumIDcount++) {
		if (RegionDensityLeft[NumIDcount] > 0 || RegionDensityRight[NumIDcount] > 0 ) {
			if (File.exists(AtlasDir + "Region_Masks/structure_" +RegionIDs[NumIDcount]+ ".nrrd")) {
				open(AtlasDir + "Region_Masks/structure_" +RegionIDs[NumIDcount]+ ".nrrd");
				rename("region");


				if (RegionDensityLeft[NumIDcount] > 0) {
					for (slice=parseInt(AtlasSizeX/2+1); slice<=AtlasSizeX; slice++) { 
	  					setSlice(slice); 
						run("Multiply...", "value="+parseInt(RegionDensityLeft[NumIDcount])+ " slice");
					}
				} else {
					for (slice=parseInt(AtlasSizeX/2+1); slice<=AtlasSizeX; slice++) {  
	  					setSlice(slice); 
						run("Subtract...", "value=1 slice");
					}
				}
				if (RegionDensityRight[NumIDcount] > 0){
					for (slice=1; slice<=parseInt(AtlasSizeX/2); slice++) { 
		  				setSlice(slice); 
						run("Multiply...", "value="+parseInt(RegionDensityRight[NumIDcount])+" slice");
					}
				} else {
					for (slice=1; slice<=parseInt(AtlasSizeX/2); slice++) { 
	  					setSlice(slice); 
						run("Subtract...", "value=1 slice");
					}
				}
				imageCalculator("Add stack", "Heatmap","region");
				close("region");

			}
		}
		if (NumIDcount == parseInt(NumIDs/4)) {
			print("     25% complete...");
		}
		if (NumIDcount == parseInt(NumIDs/2)) {
			print("\\Update:     50% complete...");
		}
		if (NumIDcount == parseInt(NumIDs/4*3)) {
			print("\\Update:     75% complete...");
		}

	}
	setMinAndMax(0, 100);
	run("Fire");
	ResliceSagittalCoronal();
	
	saveAs("Tiff", AlignDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Chan+"_Atlas_Density_Heatmap.tif");
	close();
	collectGarbage(10, 4);
	print("\\Update:     Complete.");
	}
}

function CreateSCDensityHeatmap(Chan, InputTable, OutputImage) {			
	
	//get origin front and back
	//print(" Creating density heatmap for channel "+Chan);
	ProjectionDensityOut = AlignDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron";

	if (File.exists(ProjectionDensityOut + "/"+OutputImage+".tif")) {
		print("     Projection density heatmap already created. If you wish to rerun, delete: \n     "+ProjectionDensityOut + "/"+OutputImage+".tif");
	} else {

	OpenAsHiddenResults(ProjectionDensityOut+"/"+InputTable);
	NumIDs = (nResults);
	RegionIDs = newArray(NumIDs);
	for(NumIDcount=0; NumIDcount<NumIDs; NumIDcount++) {
		RegionIDs[NumIDcount] = getResult("Region_ID", NumIDcount);
	}

	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");	

	open(AtlasDir + "Annotation_Segments_Only.tif");
	rename("Annotations");
	getDimensions(IMwidth, IMheight, channels, IMslices, frames);

	//create empty heatmap image (these are just 8bit for now so scale is % but could be 16bit for decimal places
	newImage("Heatmap", "8-bit black", AtlasSizeX, AtlasSizeY, IMslices);
	rename("Heatmap");
	for (slice=1; slice<=IMslices; slice++) {
		setSlice(slice);
		run("Set Label...", "label="+SegmentArray[slice-1]+"");
	}

	//process each region
	for(NumIDcount=0; NumIDcount<NumIDs; NumIDcount++) {
		selectWindow("Annotations");
		run("Duplicate...", "title=Annotations-Sub duplicate");
		selectWindow("Annotations-Sub");
		setThreshold(RegionIDs[NumIDcount], RegionIDs[NumIDcount]);
		run("Convert to Mask", "method=Default background=Dark black");
		run("Divide...", "value=255 stack");

		for (slice=1; slice<=IMslices; slice++) { 
			setSlice(slice); 	
			//Fill Right Region
			makeRectangle(0, 0, parseInt(AtlasSizeX/2), AtlasSizeY);
			Density = parseInt(Table.get(SegmentArray[slice-1]+"_R", NumIDcount, "Results"));
			run("Multiply...", "value="+Density+ " slice");
			
			//Fill Left Region
			makeRectangle(parseInt(AtlasSizeX/2), 0, AtlasSizeX, AtlasSizeY);
			Density = parseInt(Table.get(SegmentArray[slice-1]+"_L", NumIDcount, "Results"));
			run("Multiply...", "value="+Density+ " slice");
		}
		imageCalculator("Add stack", "Heatmap","Annotations-Sub");
		close("Annotations-Sub");
	}
	close("Annotations");
	selectWindow("Heatmap");
	// Label Segments
	setMinAndMax(0, 255);
	run("Label...", "format=Label starting=0 interval=1 x=10 y=30 font=20 text=C1 range=1-34");
	//setBatchMode("show");
	// finish and save
	setMinAndMax(0, 100);
	
	run("Fire");		
	saveAs("Tiff", ProjectionDensityOut + "/"+OutputImage+".tif");
	run("Make Montage...", "columns=6 rows=5 scale=1");
	saveAs("Tiff", ProjectionDensityOut + "/"+OutputImage+"_Montage.tif");
	close("*");
	collectGarbage(10, 4);
	print("     Complete.");
	}
}

function CreateABAIntensityHeatmapJS(Chan) {


	print("  Creating intensity map image for channel "+Chan+"...");
	MeanIntensityOut = AlignDir + "/Region_Mean_Intensity_Measurements_XY_"+ProAnRes+"_Z_"+ZCut+"micron";

	if (File.exists(MeanIntensityOut + "/C"+Chan+"_Region_Intensity_Heatmap.tif")) {
		print("     Region intensity heatmap already created. If you wish to rerun, delete: \n     "+MeanIntensityOut + "/C"+Chan+"_Region_Intensity_Heatmap.tif");
	} else {
			
		run("Region Intensity Heatmap Creation", "select=["+input+"] select_0=["+MeanIntensityOut+"] select_1=["+AtlasDir+"] cell="+Chan+" atlassizex="+AtlasSizeX+" atlassizey="+AtlasSizeY+" atlassizez="+AtlasSizeZ);
		open(MeanIntensityOut + "/C"+Chan+"_Region_Intensity_Heatmap.tif");
		ResliceSagittalCoronal();	
		saveAs("Tiff", MeanIntensityOut + "/C"+Chan+"_Region_Intensity_Heatmap.tif");
		close("*");
		collectGarbage(10, 4);
		print("     Complete.");
	}
}

function CreateABACellDensityHeatmapJS(Chan) {


	print("  Creating cell density heatmap image for channel "+Chan+"...");
	MeanIntensityOut = AlignDir + "/Cell_Analysis";

	if (File.exists(MeanIntensityOut + "/C"+Chan+"_Cell_Region_Density_Heatmap.tif")) {
		print("     Cell density heatmap already created. If you wish to rerun, delete: \n     "+MeanIntensityOut + "/C"+Chan+"_Cell_Region_Density_Heatmap.tif");
	} else {
			
		run("Region Intensity Heatmap Creation", "select=["+input+"] select_0=["+MeanIntensityOut+"] select_1=["+AtlasDir+"] cell="+Chan+" atlassizex="+AtlasSizeX+" atlassizey="+AtlasSizeY+" atlassizez="+AtlasSizeZ);
		open(MeanIntensityOut + "/C"+Chan+"_Region_Intensity_Heatmap.tif");
		ResliceSagittalCoronal();	
		saveAs("Tiff", MeanIntensityOut + "/C"+Chan+"_Cell_Region_Density_Heatmap.tif");
		File.delete(MeanIntensityOut + "/C"+Chan+"_Region_Intensity_Heatmap.tif");
		close("*");
		collectGarbage(10, 4);
		print("     Complete.");
	}
}




function CreateSCIntensityImage(Chan) {			
			
	//get origin front and back
	print("  Creating intensity map image for channel "+Chan+"...");

	if (File.exists(input+"/5_Analysis_Output/Region_Mean_Intensity_Measurements_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Chan+"_Atlas_Region_Intensity_Map.tif")) {
		print("     Projection density heatmap already created. If you wish to rerun, delete: \n     "+input+"/5_Analysis_Output/Region_Mean_Intensity_Measurements_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Chan+"_Atlas_Region_Intensity_Map.tif");
	} else {
	
	OpenAsHiddenResults(input+"/5_Analysis_Output/Region_Mean_Intensity_Measurements_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Chan+"_Mean_Region_and_Segment_Intensity.csv");
	NumIDs = (nResults);
	RegionIDs = newArray(NumIDs);
	for(NumIDcount=0; NumIDcount<NumIDs; NumIDcount++) {
		RegionIDs[NumIDcount] = getResult("Region_ID", NumIDcount);
	}

	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");	

	open(AtlasDir + "Annotation_Segments_Only.tif");
	rename("Annotations");
	getDimensions(IMwidth, IMheight, channels, IMslices, frames);

	
	//create empty heatmap image (these are just 8bit for now so scale is % but could be 16bit for decimal places
	newImage("Heatmap", "16-bit black", AtlasSizeX, AtlasSizeY, IMslices);
	rename("Heatmap");
	for (slice=1; slice<=IMslices; slice++) {
		setSlice(slice);
		run("Set Label...", "label="+SegmentArray[slice-1]+"");
	}

	//process each region
	for(NumIDcount=0; NumIDcount<NumIDs; NumIDcount++) {
		selectWindow("Annotations");
		run("Duplicate...", "title=Annotations-Sub duplicate");
		selectWindow("Annotations-Sub");
		setThreshold(RegionIDs[NumIDcount], RegionIDs[NumIDcount]);
		run("Convert to Mask", "method=Default background=Dark black");
		run("Divide...", "value=255 stack");
		run("16-bit");

		for (slice=1; slice<=IMslices; slice++) { 
			setSlice(slice); 	
			//Fill Right Region
			makeRectangle(0, 0, parseInt(AtlasSizeX/2), AtlasSizeY);
			Density = parseInt(Table.get(SegmentArray[slice-1]+"_R", NumIDcount, "Results"));
			run("Multiply...", "value="+Density+ " slice");
			
			//Fill Left Region
			makeRectangle(parseInt(AtlasSizeX/2), 0, AtlasSizeX, AtlasSizeY);
			Density = parseInt(Table.get(SegmentArray[slice-1]+"_L", NumIDcount, "Results"));
			run("Multiply...", "value="+Density+ " slice");
		}
		imageCalculator("Add stack", "Heatmap","Annotations-Sub");
		close("Annotations-Sub");
	}
	close("Annotations");
	selectWindow("Heatmap");
	Stack.getStatistics(voxelCount, mean, min, max, stdDev);
	// Label Segments
	setMinAndMax(0, 65535);
	run("Label...", "format=Label starting=0 interval=1 x=10 y=30 font=20 text=C1 range=1-34");
	run("Fire");
	setMinAndMax(0, max);
	saveAs("Tiff", input+"/5_Analysis_Output/Region_Mean_Intensity_Measurements_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Chan+"_Atlas_Region_Intensity_Map.tif");
	run("Make Montage...", "columns=6 rows=5 scale=1");
	saveAs("Tiff", input+"/5_Analysis_Output/Region_Mean_Intensity_Measurements_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Chan+"_Atlas_Region_Intensity_Map_Montage.tif");
	close("*");
	collectGarbage(10, 4);
	print("     Complete.");
	}

}

function CreateSCCellDensityHeatmapImage (Chan) {
			
	//get origin front and back
	print("  Creating cell density heatmap image for channel "+Chan+"...");

	if (File.exists(input+"/5_Analysis_Output/Cell_Analysis/C"+Chan+"_Atlas_Region_Cell_Density_Heatmap.tif")) {
		print("     Cell density heatmap already created. If you wish to rerun, delete: \n     "+input+"/5_Analysis_Output/Cell_Analysis/C"+Chan+"_Atlas_Region_Cell_Density_Heatmap.tif");
	} else {
	
	OpenAsHiddenResults(input+"/5_Analysis_Output/Cell_Analysis/C"+Chan+"_Region_and_Segment_Cell_Density_mm3.csv");
	NumIDs = (nResults);
	RegionIDs = newArray(NumIDs);
	for(NumIDcount=0; NumIDcount<NumIDs; NumIDcount++) {
		RegionIDs[NumIDcount] = getResult("Region_ID", NumIDcount);
	}

	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");	

	open(AtlasDir + "Annotation_Segments_Only.tif");
	rename("Annotations");
	getDimensions(IMwidth, IMheight, channels, IMslices, frames);
	
	//create empty heatmap image (these are just 8bit for now so scale is % but could be 16bit for decimal places
	newImage("Heatmap", "16-bit black", AtlasSizeX, AtlasSizeY, IMslices);
	rename("Heatmap");
	for (slice=1; slice<=IMslices; slice++) {
		setSlice(slice);
		run("Set Label...", "label="+SegmentArray[slice-1]+"");
	}

	//process each region
	for(NumIDcount=0; NumIDcount<NumIDs; NumIDcount++) {
		selectWindow("Annotations");
		run("Duplicate...", "title=Annotations-Sub duplicate");
		selectWindow("Annotations-Sub");
		setThreshold(RegionIDs[NumIDcount], RegionIDs[NumIDcount]);
		run("Convert to Mask", "method=Default background=Dark black");
		run("Divide...", "value=255 stack");
		run("16-bit");

		for (slice=1; slice<=IMslices; slice++) { 
			setSlice(slice); 	
			//Fill Right Region
			makeRectangle(0, 0, parseInt(AtlasSizeX/2), AtlasSizeY);
			Density = parseInt(Table.get(SegmentArray[slice-1]+"_R", NumIDcount, "Results"));
			run("Multiply...", "value="+Density+ " slice");
			
			//Fill Left Region
			makeRectangle(parseInt(AtlasSizeX/2), 0, AtlasSizeX, AtlasSizeY);
			Density = parseInt(Table.get(SegmentArray[slice-1]+"_L", NumIDcount, "Results"));
			run("Multiply...", "value="+Density+ " slice");
		}
		imageCalculator("Add stack", "Heatmap","Annotations-Sub");
		close("Annotations-Sub");
	}
	close("Annotations");
	selectWindow("Heatmap");
	Stack.getStatistics(voxelCount, mean, min, max, stdDev);
	// Label Segments
	setMinAndMax(0, 65535);
	run("Label...", "format=Label starting=0 interval=1 x=10 y=30 font=20 text=C1 range=1-34");
	run("Fire");
	setMinAndMax(0, max);
	saveAs("Tiff", input+"/5_Analysis_Output/Cell_Analysis/C"+Chan+"_Atlas_Region_Cell_Density_Heatmap.tif");
	run("Make Montage...", "columns=6 rows=5 scale=1");
	saveAs("Tiff", input+"/5_Analysis_Output/Cell_Analysis/C"+Chan+"_Atlas_Region_Cell_Density_Heatmap.tif");
	close("*");
	collectGarbage(10, 4);
	print("     Complete.");
	}

}


function DeleteFile(Filelocation){
	if (File.exists(Filelocation)) {
		a=File.delete(Filelocation);
	}
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

function append(arr, value) {
	 arr2 = newArray(arr.length+1);
	 for (i=0; i<arr.length; i++)
	    arr2[i] = arr[i];
	 arr2[arr.length] = value;
	 return arr2;
}
function sumColumnTab (kind) {
	sum=0;
	if (columnLabelList (kind) >=0) {
		for (a=0; a<nResults(); a++) {
			sum=sum+getResult(kind,a);
		}
	return sum;
	}
}
function columnLabelList (kind) {

	columnNumber=-1;
	if (nResults() > 0 && isOpen("Results")) {
		selectWindow("Results");
   		results = getInfo();
   		lines = split(results, "\n");
  		headings = lines[0];
		titlesofcolumns = split(headings, ",\t");
		for (a=0; a<titlesofcolumns.length; a++) {if (titlesofcolumns[a] == kind) columnNumber=a;}
	}
	return columnNumber;
}
function CloseOpenWindowsNew(){
	listwindows = getList("window.titles");
	if (listwindows.length > 0) {
		for (list=0; list<listwindows.length; list++) {
			if (listwindows[list] != "Recorder" && listwindows[list] != "Log" && listwindows[list] != "Debug" && listwindows[list] != "B&C") {
				selectWindow(listwindows[list]);
				run("Close");
			}
		}
	}
}

function num2array(str,delim){
	arr = split(str,delim);
	for(i=0; i<arr.length;i++) {
		arr[i] = parseInt(arr[i]);
	}

	return arr;
}
function measure_int_manual_cells(CellChan) {
	print("Measuring itensities for channel: "+CellChan+"...");

	if (File.exists(input + "5_Analysis_Output/Cell_Analysis/C"+CellChan+"_Detected_Cells_Summary.csv")) {
		print("     Cell analysis for channel "+CellChan+" already performed. If you wish to rerun, delete directory: "+input + "5_Analysis_Output/Cell_Analysis/");
	} else {

		//DeleteFile(CellCountOut + "Cell_Points_Ch"+CellChan+".csv");
		DeleteFile(CellIntensityOut + "Cell_Points_with_intensities_Ch"+CellChan+".csv");
	
	
		CellLocations = input + "4_Processed_Sections/Detected_Cells/Cell_Points_Ch"+CellChan+".csv";
		//make sure headings aren't saved
		run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file");
		// measurement settings
		run("Set Measurements...", "centroid stack redirect=None decimal=3");
		// apply threshold
	
		//Open existing cell locations
		open(CellLocations);
		Table.rename(Table.title, "Results");
		
		//Store cooridinates to readout later
		CountROI=nResults;
		XCoordinate = newArray(CountROI);
		YCoordinate = newArray(CountROI);
		ZCoordinate = newArray(CountROI);
		for(j=0; j<CountROI; j++) {
			XCoordinate[j] = getResult("C1", j);
			YCoordinate[j] = getResult("C2", j);
			ZCoordinate[j] = getResult("C3", j);
		}
		
		run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file");
		close("Results");
	
		// Measure intensities of all channels not AF and create validation images
		print("    Measuring intensities...");
		for(chl=1; chl<5; chl++) {
			

			if (File.exists(RegDir + chl) && chl != AlignCh ) {
	 			//open the stack
	 			RawSections = getFileList(RegDir +chl);
	 			RawSections = Array.sort( RawSections );
	 			Section1 = RawSections[0];
	 			run("Image Sequence...", "open=["+ RegDir + chl + "/" + Section1 + "] scale=100 sort");
	 			run("Properties...", "pixel_width=1 pixel_height=1 voxel_depth=1");
	 			
	 			rename("RawStack");
	 			getDimensions(Drwidth, Drheight, DrChNum, Drslices, Drframes);
	 			run("Set Measurements...", "mean redirect=None decimal=3");
	
	 			// for each ROI
	 			setTool("point");
	 			for(n=0; n<CountROI;n++) { 
					setSlice(ZCoordinate[n]);
					makePoint(XCoordinate[n], YCoordinate[n], "medium yellow hybrid");
					run("Measure");
				}

				if (chl == 1) {
					print("    Measuring intensities for channel " + chl);
					MeasMeanInt1 = newArray(CountROI);
					for(j=0; j<CountROI; j++) {
						MeasMeanInt1[j] = getResult("Mean", j);
					}
					close("Results");
					if (chl == CellChan) {
						selectWindow("RawStack");
						rename("RawChStack");
					}
					if (chl == CellChan && IntVal == true) {
						newImage("Masks", "16-bit black", Drwidth, Drheight, Drslices);
						for(n=0; n<CountROI;n++) { 
							roiManager("Select", n);
							run("Add...", "value="+MeasMeanInt1[n]+" slice");
						}
					}
					
				}
				if (chl == 2) {
					print("    Measuring intensities for channel " + chl);
					MeasMeanInt2 = newArray(CountROI);
					for(j=0; j<CountROI; j++) {
						MeasMeanInt2[j] = getResult("Mean", j);
					}
					close("Results");
					if (chl == CellChan) {
						selectWindow("RawStack");
						rename("RawChStack");
					}
					if (chl == CellChan && IntVal == true) {
						newImage("Masks", "16-bit black", Drwidth, Drheight, Drslices);
						for(n=0; n<CountROI;n++) { 
							roiManager("Select", n);
							run("Add...", "value="+MeasMeanInt2[n]+" slice");
						}
					}
					
				}
				if (chl == 3) {
					print("     Measuring intensities for channel " + chl);
					MeasMeanInt3 = newArray(CountROI);
					for(j=0; j<CountROI; j++) {
						MeasMeanInt3[j] = getResult("Mean", j);
					}
					close("Results");
					if (chl == CellChan) {
						selectWindow("RawStack");
						rename("RawChStack");
					}
					if (chl == CellChan && IntVal == true) {
						newImage("Masks", "16-bit black", Drwidth, Drheight, Drslices);
						for(n=0; n<CountROI;n++) { 
							roiManager("Select", n);
							run("Add...", "value="+MeasMeanInt3[n]+" slice");
						}
					}
				}
				if (chl == 4) {
					print("    Measuring intensities for channel " + chl);
					MeasMeanInt4 = newArray(CountROI);
					for(j=0; j<CountROI; j++) {
						MeasMeanInt4[j] = getResult("Mean", j);
					}
					close("Results");
					if (chl == CellChan) {
						selectWindow("RawStack");
						rename("RawChStack");
					}
					if (chl == CellChan && IntVal == true) {
						newImage("Masks", "16-bit black", Drwidth, Drheight, Drslices);
						for(n=0; n<CountROI;n++) { 
							roiManager("Select", n);
							run("Add...", "value="+MeasMeanInt4[n]+" slice");
						}
					}
				}
				
	 		} else {
	 			if (chl == 1) {
	 				MeasMeanInt1 = newArray(CountROI);
	 			}
	 			if (chl == 2) {
	 				MeasMeanInt2 = newArray(CountROI);
	 			}
	 			if (chl == 3) {
	 				MeasMeanInt3 = newArray(CountROI);
	 			}
	 			if (chl == 4) {
	 				MeasMeanInt4 = newArray(CountROI);
	 			}
	 		}
	 	close("RawStack");	
		}
		cleanupROI();
		run("Close All");
		close("Results");
		
		run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file save_column");
		

		////// Create a annotated table ////
		print("     Saving cell locations and measured intensities.");

		// Set a filename:
		CellFileOut = CellIntensityOut + "Cell_Points_with_intensities_Ch"+CellChan+".csv";
		
		// 1) Delete file if it exists - otherwise can produce error:
		if (File.exists(CellFileOut) ==1 ) {
			File.delete(CellFileOut);
		}
		
		// 2) Open file to write into
		WriteOut = File.open(CellFileOut);
		
		// 3) Print headings
		print(WriteOut, "X,Y,Z,Mean_Int_Ch1,Mean_Int_Ch2,Mean_Int_Ch3,Mean_Int_Ch4\n");

		// 4) Print lines
		for(j=0; j<CountROI; j++){ 
			print(WriteOut, XCoordinate[j]+","+YCoordinate[j]+","+ZCoordinate[j]+","+MeasMeanInt1[j]+","+MeasMeanInt2[j]+","+MeasMeanInt3[j]+","+MeasMeanInt4[j]);
		} 

		// 5) Close file
		File.close(WriteOut);
		
		close("Results"); 
		print("    Complete.");
	  	close("*");
	}
	
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

function Locate2Values(inputArray, VarName) {
		
	//Give array name, and variable name in column 0, returns value in column 1
	Found = 0;
	for(i=0; i<inputArray.length; i++){ 
		if(matches(inputArray[i],".*"+VarName+".*") == 1 ){
			Row = split(inputArray[i], ",");
			if (Row.length > 2) {
				Value = Row[1]+"," + Row[2];
			} else {
				Value = 0;
			}
			Found = 1; 	
		}	
	}
	if (Found == 0) {
		Value = 0;
	}
	return Value;
}


function LocateID(RegionArray, VarName) {	
	//Give array name, and variable name in column 0, returns value in column 1
	Found = 0;
	for(i=0; i<RegionArray.length; i++){ 
		if(RegionArray[i] == VarName){
			Value = i;
			Found = 1; 	
		}	
	}
	if (Found == 0) {
		Value = 0;
	}
	return Value;
}




function CreateDAPIMask (input) {
	if (File.exists(RegDir + "DAPI_25_Mask.tif") == 0) {
		open(input+"3_Registered_Sections/DAPI_25.tif");
		setAutoThreshold("Li dark");
		run("Convert to Mask", "method=Li background=Dark calculate black");
		run("Dilate", "stack");
		run("Dilate", "stack");
		saveAs("Tiff", input+"3_Registered_Sections/DAPI_25_Mask.tif");
		close();
	}
}

function UpdateTransParamLocation0 (ParamFileLocation) {
	//Param file location should be e.g.: input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.1.txt"

	filestring=File.openAsString(ParamFileLocation); 
	rows=split(filestring, "\n"); 
	
	for(i=0; i<rows.length; i++){ 
		if(matches(rows[i],".*InitialTransformParametersFileName.*") == 1 ){
			ParamRow=i;
		}
	}		
					
	//Create new array lines
	newParam ="(InitialTransformParametersFileName "+q + input + "5_Analysis_Output/Transform_Parameters/Cell_TransformParameters.0.txt"+q+")";
					
	//Update Array lines
	rows[ParamRow] = newParam;
		
	// Set a filename:
	CellFileOut = ParamFileLocation;
		
	// 1) Delete file if it exists - otherwise can produce error:
	File.delete(CellFileOut);
		
	// 2) Open file to write into
	WriteOut = File.open(CellFileOut);
		
	// 3) Print lines
	for(i=0; i<rows.length; i++){ 
		print(WriteOut, rows[i] + "\n");
	}

	File.close(WriteOut);
}	

function CreateCellHeatmap(CellChan) {
	print("  Creating cell heatmaps for channel "+CellChan+" ...");
	
	if (File.exists(input + "5_Analysis_Output/Cell_Analysis/C"+CellChan+"_Cells_Heatmap.tif")) {
		print("     Cell heatmpas already created. If you wish to rerun, delete : "+input + "5_Analysis_Output/Cell_Analysis/C"+CellChan+"_Cells_Heatmap.tif");
	} else {

	celloutput = input + "5_Analysis_Output/Cell_Analysis/";
	
	run("Cell Heatmap Creation", "select=["+input+"] select_0=["+celloutput+"] cell="+CellChan+" atlassizex="+AtlasSizeX+" atlassizey="+AtlasSizeY+" atlassizez="+AtlasSizeZ);

		print("   Density heatmap complete.");
	}
}

function TransformRawDataToAtlas() {
	//Count number of channel folders in Registered Directory
	ChNum = CountFolders(input+ "/3_Registered_Sections/");
	
	//Count number of registered slices
	RegSectionsCount = getFileList(input+ "/3_Registered_Sections/1/");	
	RegSectionsCount = RegSectionsCount.length;		
		
	// 1) Elastix Inverse Transform Align Image to Template
	ProTstarttime = getTime();
	print("Preparing to transform raw data into atlas space...");
	if (File.exists(input + "5_Analysis_Output/Transform_Parameters/RawDataTransformParameters.txt")) {
		print("     Alignment already performed, using existing transform parameters.");
	} else {
		print("     Performing alignment and creating transform parameters...");
		ElastixCmd = Elastix +" -f "+ExpBrain+" -m "+ExpBrain+" -t0 "+TransP+" -out "+InvOut+" -p "+InvBSpline;
		
		CreateBatFile (ElastixCmd, input, "Elastixrun");
		runCmd = CreateCmdLine(input + "Elastixrun.bat");
		exec(runCmd);
		
		DeleteFile(input+"Elastixrun.bat");
	
		print("     Alignment complete.");
				
		// 2) Modify Inv Transform Parameters - NoInitialTransform and Size/Index/Spacing/Origin/Direction set to the atlas space

		open(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv");
		Table.rename(Table.title, "Results");
		IndexOrigin=parseInt(getResult("X", 0));
		IndexEnd=parseInt(getResult("X", 1));
		close("Results");

		filestring=File.openAsString(input + "5_Analysis_Output/Temp/InvOut/TransformParameters.0.txt"); 

		rows=split(filestring, "\n"); 
		//Search for required rows
		
		for(i=0; i<rows.length; i++){ 
			if(matches(rows[i],".*InitialTransformParametersFileName.*") == 1 ){
				ParamRow=i;
			}
			if(matches(rows[i],".*FinalBSplineInterpolationOrder.*") == 1) {
				BSplineRow=i;
			}
			if(matches(rows[i],".*Size.*") == 1 && matches(rows[i],".*GridSize.*") == 0){
				SizeRow=i;
			}
			if(matches(rows[i],".*Index.*") == 1 && matches(rows[i],".*GridIndex.*") == 0){
				IndexRow=i;
			}
			if(matches(rows[i],".*Spacing.*") == 1 && matches(rows[i],".*GridSpacing.*") == 0){
				SpacingRow=i;
			}
			if(matches(rows[i],".*Origin.*") == 1 && matches(rows[i],".*GridOrigin.*") == 0){
				OriginRow=i;
			}
			if(matches(rows[i],".*FinalBsplineInterpolationOrder.*") == 1) {
				BSplineRow=i;
			}
			if(matches(rows[i],".*ResultImagePixelType.*") == 1) {
				ResultPixelTypeRow=i;
			}
		}

		//Create new array lines
		newParam ="(InitialTransformParametersFileName "+q+"NoInitialTransform"+q+")";
		rows[ParamRow] = newParam;
		
		//if (ProAnRes != 25) {
		//	newSize = "(Size "+parseInt(AtlasSizeX/(ProAnResSection/25))+" "+parseInt(AtlasSizeY/(ProAnRes/25))+" "+parseInt(AtlasSizeZ/(ProAnRes/25))+")";
		//} else {
			newSize = "(Size "+AtlasSizeX+" "+AtlasSizeY+" "+AtlasSizeZ+")";
		//}
		rows[SizeRow] = newSize;
		
		newBSpline = "(FinalBSplineInterpolationOrder 3)";
		rows[BSplineRow] = newBSpline;

		ResultPixelType ="(ResultImagePixelType "+q+"float"+q+")";
		rows[ResultPixelTypeRow] = ResultPixelType;
		
		//SET UP CORRECT SPACING if not isotropic - refer to AtlasResXY and AtlasResZ from Atlas file
		
			//if (ProAnRes != 25) {
			//	FinalSpacingX = ProAnResSection/25;
			//	FinalSpacingY = ProAnRes/25;
			//	//Possibly add alternative line here to address different section thickness <25? Could require a lot of memory for 32bit image of whole brain though.
			//	FinalSpacingZ = ProAnRes/25;
			//}
			//newSpacing = "(Spacing "+FinalSpacingX+" "+FinalSpacingY+" "+FinalSpacingZ+")";
			//rows[SpacingRow] = newSpacing;
	
			//newOrigin = "(Origin "+(IndexOrigin*-1)+" 0 0)";
		
		// Create and save parameters
		run("Text Window...", "name=NewTransParameters");
		for(i=0; i<rows.length; i++){ 
			print("[NewTransParameters]", rows[i] + "\n");
		}
	
		selectWindow("NewTransParameters");
		run("Text...", "save=["+ input + "5_Analysis_Output/Transform_Parameters/RawDataTransformParameters.txt]");
		
		close("RawDataTransformParameters.txt");
		DeleteDir(input + "5_Analysis_Output/Temp/InvOut/");

		print("     Transform parameters created.");
	}	
	
	ProTendtime = getTime();
	dif = (ProTendtime-ProTstarttime)/1000;
	print("Registration and preparing transformation files processing time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");

	// CREATE THE ISOTROPIC VOLUMES
	// Changed to only use 25 um isotropic rather than using ProAnRes and ProAnResSection
	
	//print("Creating "+ProAnRes+"um isotropic volumes...");
	print("Creating "+AtlasResXY+"um isotropic volumes...");
		
	SPstarttime = getTime();

	if (File.exists(input + "5_Analysis_Output/Transform_Parameters/RawDataTransformParameters.txt")) {

		for(j=1; j<ChNum+1; j++) {	
			Sections = getFileList(input+"/3_Registered_Sections/"+j);
			//print(" Creating "+ProAnRes+"um lateral with "+ProAnResSection+" section thickness volumes with raw data for channel "+j);		
			//coronalto3Dsagittal(input + "3_Registered_Sections/" +j, input+"/3_Registered_Sections", "C"+j+"_Sagittal", ProAnRes, ZCut);
			
			print(" Creating "+AtlasResXY+"um lateral with "+AtlasResZ+" section thickness volumes with raw data for channel "+j); 	
			coronalto3Dsagittal(RegDir +j, input+"/3_Registered_Sections", "C"+j+"_25", AtlasResXY, ZCut);
	
			if (File.exists(input + "4_Processed_Sections/Enhanced/" +j)) {
					EnSectionsCount = getFileList(input + "4_Processed_Sections/Enhanced/" +j);	
					if (RegSectionsCount == EnSectionsCount.length){
						//print(" Creating "+ProAnRes+"um lateral with "+ProAnResSection+" section thickness volumes with background subtracted data for channel "+j);
						print(" Creating "+AtlasResXY+"um lateral with "+AtlasResZ+" section thickness volumes with background subtracted data for channel "+j);
						//coronalto3Dsagittal(input + "4_Processed_Sections/Enhanced/" +j, input+"/3_Registered_Sections", "C"+j+"_SagittalBGSub", ProAnRes, ZCut);
						coronalto3Dsagittal(input + "4_Processed_Sections/Enhanced/" +j, input+"/3_Registered_Sections", "C"+j+"_25_BGSub", AtlasResXY, ZCut);
					}
			}
					
			
			collectGarbage(10, 4);
		}
		SPendtime = getTime();
		dif = (SPendtime-SPstarttime)/1000;
		print("Raw sagittal image creation processing time: ", (dif/60), " minutes.");
		print("---------------------------------------------------------------------------------------------------------------------");
			

		//Transform images to ABA space
		TBstarttime = getTime();
	
		File.mkdir(input + "5_Analysis_Output/Temp/Transformed_Raw_Out");
		File.mkdir(TransformedRawDataOut);
		
		
		InvTransPModRawData = CreateCmdLine(input + "5_Analysis_Output/Transform_Parameters/RawDataTransformParameters.txt");
		
		open(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv");
		Table.rename(Table.title, "Results");
		IndexOrigin=parseInt(getResult("Z", 0));
		IndexEnd=parseInt(getResult("Z", 1));
		close("Results");
		
		for(j=1; j<ChNum+1; j++) {	
			print("Transforming raw data for channel "+j+" to atlas space...");
	
			if (File.exists(TransformedRawDataOut+"C"+j+"_raw_data_in_atlas_space.tif")) {
				print("     Projection density heatmap already created. If you wish to rerun, delete : \n     "+TransformedRawDataOut+"C"+j+"_raw_data_in_atlas_space.tif");
			} else {
		
						
				TransformedRawData = input + "5_Analysis_Output/Temp/Transformed_Raw_Out/result.mhd";
				RawImageForTrans = CreateCmdLine(RegDir + "C"+j+"_25.tif");
				TempTransImageOut = CreateCmdLine(input + "5_Analysis_Output/Temp/Transformed_Raw_Out");
		
				TransformCmd = Transformix +" -in "+RawImageForTrans+" -tp "+InvTransPModRawData+" -out "+TempTransImageOut;
				
				CreateBatFile (TransformCmd, input, "TransformixRun");
				runCmd = CreateCmdLine(input + "TransformixRun.bat");
				exec(runCmd);
				print(" Image transformation complete.");
				print("   ");
				
				run("MHD/MHA...", "open=["+ TransformedRawData+"]");
				
				rename("RawData");
				setMinAndMax(0, 65535);
				run("16-bit");
				resetMinAndMax();
				
				//if (ProAnRes != 25) {
				//	makeRectangle((parseInt(IndexOrigin*(1/(ProAnRes/25)))+parseInt(6*(1/(ProAnRes/25)))), 0, (parseInt(IndexEnd*(1/(ProAnRes/25)))-parseInt(IndexOrigin*(1/(ProAnRes/25)))-parseInt(6*(1/(ProAnRes/25)))), parseInt(320*(1/(ProAnRes/25))));
				//	
				//} else {
					//crop out density analysis region - currently using -5 to be conservative, potentially use better origin points
			 	ResliceSagittalCoronal();
			 	
			 	makeRectangle((IndexOrigin+Trim), 0, (IndexEnd-IndexOrigin-Trim), AtlasSizeY);
	
			 		 		 		
				//}
				run("Clear Outside", "stack");
				run("Select None");
	
				ResliceSagittalCoronal();
				rename("RawData");
				
				//Open template make binary and multipy with raw data to clean up
				open(AtlasDir + "Template.tif");
				rename("Template");
		
				setMinAndMax(7, 7);
				run("Apply LUT", "stack");
				run("8-bit");
				run("Subtract...", "value=254 stack");
				imageCalculator("Multiply create stack", "RawData","Template");
				selectWindow("Result of RawData");
				if (OutputType == "Sagittal") {
					ResliceSagittalCoronal();
				}
				
				saveAs("Tiff", TransformedRawDataOut+"C"+j+"_raw_data_in_atlas_space.tif");
				close("*");
			}
				
		}	
	
		DeleteFile(input+"TransformixRun.bat");
		DeleteDir(input + "5_Analysis_Output/Temp/Transformed_Raw_Out/");
		collectGarbage(10, 4);	
	
		TBendtime = getTime();
		dif = (TBendtime-TBstarttime)/1000;
		print("Raw channel transformation processing time: ", (dif/60), " minutes.");
		print("---------------------------------------------------------------------------------------------------------------------");
		VisRegCheck = 0;
	} else {
			VisRegCheck = 1;
			print("     Registration process for generating visualizations of raw data and projections in atlas space failed.");
			print("     Visualizations of projections and raw data in atlas space won't be available but all other analysis is unaffected");
			print("     To resolve this issue, check \5_Analysis_Output\template_brain_aligned.tif and explore ways to improve registration (e.g. replace damaged sections)");	
	}
return VisRegCheck;
}

function TransformBinaryDataToAtlas(Channel) {
	
	close("Results");
	// CREATE ISOTROPIC VOLUMES
	// Changed to only use 25 um isotropic rather than using ProAnRes and ProAnResSection
	
	print("Creating "+AtlasResXY+"um isotropic projection volumes...");
	if (File.exists(RegDir+ "C"+Channel+"_25_Binary.tif")) {
			print("     Isotropic projection density image already created.");
		} else {
			print("   Importing projection data for density analysis...");
	
			if (ProjDetMethod == "Binary Threshold") {
				inputdir = input + "4_Processed_Sections/Enhanced/"+Channel;
				rawSections = getFileList(inputdir);
				rawSections = Array.sort( rawSections );
				Section1 = rawSections[0];
				run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=100 sort");
			}
			if (ProjDetMethod == "Machine Learning Segmentation with Ilastik") {
				inputdir = input + "4_Processed_Sections/Probability_Masks/"+Channel;
				rawSections = getFileList(inputdir);
				rawSections = Array.sort( rawSections );
				Section1 = rawSections[0];
				run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=100 sort");
				rename("Stack");
				run("Split Channels");
				selectWindow("Stack (green)");
				close("\\Others");
							
			}
	
			setAutoThreshold("Default dark stack");
			setThreshold(ProBGround, 255);
			run("Convert to Mask", "method=Default background=Dark black");
			run("Properties...", "unit=micron pixel_width="+FinalRes+" pixel_height="+FinalRes+" voxel_depth="+ZCut+"");

			// Create sagittal image at Atlas Resolution for visualization.
			print("   Creating binary dataset at "+AtlasResXY+" micron for transformation and visualization.");
			scaleX = FinalRes/AtlasResXY;
			scaleZ = ZCut/AtlasResZ;
			run("Scale...", "x="+scaleX+" y="+scaleX+" z="+scaleZ+" interpolation=None process create");
			//rename("TempScale");
			//run("Reslice [/]...", "output=25 start=Left rotate avoid");
			saveAs("Tiff",  RegDir+ "C"+Channel+"_25_Binary.tif");
			close("*");	
		}

		//Transform images to ABA space
		TBstarttime = getTime();

		File.mkdir(input + "5_Analysis_Output/Temp/Transformed_Binary_Out");
		InvTransPMod = CreateCmdLine(input + "5_Analysis_Output/Transform_Parameters/ProjectionTransformParameters.txt");


		open(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv");
		Table.rename(Table.title, "Results");
		IndexOrigin=parseInt(getResult("Z", 0));
		IndexEnd=parseInt(getResult("Z", 1));
		close("Results");
		


		print("Transforming binary projection data for channel "+Channel+" to atlas space...");

		if (File.exists(TransformedProjectionDataOut+"C"+Channel+"_binary_projection_data_in_atlas_space.tif")) {
			print("     Projection density heatmap already created. If you wish to rerun, delete : \n     "+TransformedProjectionDataOut+"C"+Channel+"_binary_projection_data_in_atlas_space.tif");
		} else {

				
		TransformedBinaryData = input + "5_Analysis_Output/Temp/Transformed_Binary_Out/result.mhd";
		ImageForTrans = CreateCmdLine(RegDir + "C"+Channel+"_25_Binary.tif");
		TempTransImageOut = CreateCmdLine(input + "5_Analysis_Output/Temp/Transformed_Binary_Out");

		TransformCmd = Transformix +" -in "+ImageForTrans+" -tp "+InvTransPMod+" -out "+TempTransImageOut;
		
		CreateBatFile (TransformCmd, input, "TransformixRun");
		runCmd = CreateCmdLine(input + "TransformixRun.bat");
		exec(runCmd);
		print(" Image transformation complete.");
		print("   ");
		
		if (File.exists(TransformedBinaryData)) {
			run("MHD/MHA...", "open=["+ TransformedBinaryData+"]");
			
			rename("RawData");
		
			run("8-bit");
			resetMinAndMax();
			
		 	ResliceSagittalCoronal();
		 	
		 	makeRectangle((IndexOrigin+Trim), 0, (IndexEnd-IndexOrigin-Trim), AtlasSizeY);
			//print(IndexOrigin, IndexEnd, AtlasSizeY);
			run("Clear Outside", "stack");
			run("Select None");
		
			ResliceSagittalCoronal();
			rename("RawData");
			
			//Open template make binary and multipy with raw data to clean up
			open(AtlasDir + "Template.tif");
			rename("Template");
		
			setMinAndMax(7, 7);
			run("Apply LUT", "stack");
			run("8-bit");
			run("Subtract...", "value=254 stack");
			imageCalculator("Multiply create stack", "RawData","Template");
			selectWindow("Result of RawData");
			if (OutputType == "Sagittal") {
				ResliceSagittalCoronal();
			}
			
			saveAs("Tiff", TransformedProjectionDataOut+"C"+Channel+"_binary_projection_data_in_atlas_space.tif");
			close("*");
			VisRegCheck = 0;
		} else {
			VisRegCheck = 1;
		}
	}
		

	DeleteFile(input+"TransformixRun.bat");
	DeleteDir(input + "5_Analysis_Output/Temp/Transformed_Binary_Out/");
	collectGarbage(10, 4);	
	return VisRegCheck;

}

function PerformReverseTransformationForProjections() {

// 1) Elastix Inverse Transform Align Image to Template
	ProTstarttime = getTime();
	print("Performing projection analysis...");
	print("Transforming projections...");
	if (ProCh > 0 ) {
	
		if (File.exists(input + "5_Analysis_Output/Transform_Parameters/ProjectionTransformParameters.txt")) {
			print("     Neuronal projection alignment already performed, using existing transform parameters.");
						
		} else {
			print("     Performing neuronal projection alignment and creating transform parameters...");
			ElastixCmd = Elastix +" -f "+ExpBrain+" -m "+ExpBrain+" -t0 "+TransP+" -out "+InvOut+" -p "+InvBSpline;
			
			CreateBatFile (ElastixCmd, input, "Elastixrun");
			runCmd = CreateCmdLine(input + "Elastixrun.bat");
			exec(runCmd);
			
			DeleteFile(input+"Elastixrun.bat");
		
			print("     Projection alignment complete.");
		
		// 2) Modify Inv Transform Parameters - NoInitialTransform and Size/Index/Spacing/Origin/Direction set to the atlas space

			open(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv");
			Table.rename(Table.title, "Results");
			IndexOrigin=parseInt(getResult("Z", 0));
			IndexEnd=parseInt(getResult("Z", 1));
			close("Results");

			//run("Text File... ", "open=["+input + "5_Analysis_Output/Temp/Template_aligned/TransformParameters.1.txt]");
			filestring=File.openAsString(input + "5_Analysis_Output/Temp/InvOut/TransformParameters.0.txt"); 
			//filestring=File.openAsString(pathfile); 

			rows=split(filestring, "\n"); 
			//Search for required rows
			
			for(i=0; i<rows.length; i++){ 
				if(matches(rows[i],".*InitialTransformParametersFileName.*") == 1 ){
					ParamRow=i;
				}
				if(matches(rows[i],".*FinalBSplineInterpolationOrder.*") == 1) {
					BSplineRow=i;
				}
				if(matches(rows[i],".*Size.*") == 1 && matches(rows[i],".*GridSize.*") == 0){
					SizeRow=i;
				}
				if(matches(rows[i],".*Index.*") == 1 && matches(rows[i],".*GridIndex.*") == 0){
					IndexRow=i;
				}
				if(matches(rows[i],".*Spacing.*") == 1 && matches(rows[i],".*GridSpacing.*") == 0){
					SpacingRow=i;
				}
				if(matches(rows[i],".*Origin.*") == 1 && matches(rows[i],".*GridOrigin.*") == 0){
					OriginRow=i;
				}
				if(matches(rows[i],".*FinalBsplineInterpolationOrder.*") == 1) {
					BSplineRow=i;
				}
				if(matches(rows[i],".*ResultImagePixelType.*") == 1) {
					ResultPixelTypeRow=i;
				}
			}
		
			//Create new array lines
			newParam ="(InitialTransformParametersFileName "+q+"NoInitialTransform"+q+")";

			newSize = "(Size "+AtlasSizeX+" "+AtlasSizeY+" "+AtlasSizeZ+")";

			// only add if binary - else leave as is.
			newBSpline = "(FinalBSplineInterpolationOrder 0)";
	
			//Update Array lines
			rows[ParamRow] = newParam;
			rows[SizeRow] = newSize;
			rows[BSplineRow] = newBSpline;
		
			run("Text Window...", "name=NewTransParameters");
			for(i=0; i<rows.length; i++){ 
				print("[NewTransParameters]", rows[i] + "\n");
			}
		
			selectWindow("NewTransParameters");
			run("Text...", "save=["+ input + "5_Analysis_Output/Transform_Parameters/ProjectionTransformParameters.txt]");
			
			close("ProjectionTransformParameters.txt");
			DeleteDir(input + "5_Analysis_Output/Temp/InvOut/");

			// CREATE RAW DATA TRANSFORMATION PARAMETERS
			
			//set new parameters
			newBSpline = "(FinalBSplineInterpolationOrder 3)";
			rows[BSplineRow] = newBSpline;
			ResultPixelType ="(ResultImagePixelType "+q+"float"+q+")";
			rows[ResultPixelTypeRow] = ResultPixelType;

			// Create and save parameters
			run("Text Window...", "name=NewTransParameters");
			for(i=0; i<rows.length; i++){ 
				print("[NewTransParameters]", rows[i] + "\n");
			}
		
			selectWindow("NewTransParameters");
			run("Text...", "save=["+ input + "5_Analysis_Output/Transform_Parameters/RawDataTransformParameters.txt]");
			
			close("RawDataTransformParameters.txt");
			DeleteDir(input + "5_Analysis_Output/Temp/InvOut/");
			
			if (File.exists(input + "5_Analysis_Output/Transform_Parameters/ProjectionTransformParameters.txt")) {
				print("     Transform parameters created.");
				VisRegCheck = 0;
			} else {
				VisRegCheck = 1;
				print("     Registration process for generating visualizations of raw data and projections in atlas space failed.");
				print("     Visualizations of projections and raw data in atlas space won't be available but all other analysis is unaffected");
				print("     To resolve this issue, check \5_Analysis_Output\template_brain_aligned.tif and explore ways to improve registration (e.g. replace damaged sections)");

			}
	

	}		
	
	ProTendtime = getTime();
	dif = (ProTendtime-ProTstarttime)/1000;
	print("Projection transformation processing time: ", (dif/60), " minutes.");
	print("---------------------------------------------------------------------------------------------------------------------");

	}
return VisRegCheck;
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


		// Create and transform hemisphere location image - left is 0 right is 1.
		if (AtlasType == "Spinal Cord") {
			HemisphereImage = CreateCmdLine(AtlasDir + "Hemisphere_Annotation.tif");

		} else {

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
		}		
		
		TransformCmd = Transformix +" -in "+HemisphereImage+" -tp "+AnnTransParam+" -out "+AnnotationImageOut;

		CreateBatFile (TransformCmd, input, "TransformixRun");
		runCmd = CreateCmdLine(input + "TransformixRun.bat");
		exec(runCmd);
		
		run("MHD/MHA...", "open=["+ input + "5_Analysis_Output/Temp/AnnOut/result.mhd]");
		run("8-bit");
		run("Size...", "depth="+RegSectionsCount+" interpolation=None");
		saveAs("Tiff", input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif");
		close("*");	


		if (AtlasType == "Spinal Cord") {
			// Create and transform hemisphere location image - left is 0 right is 1.
			open(AtlasDir + "Segment_Annotations.tif");
			run("Scale...", "x="+AtlasSizeX+" y="+AtlasSizeY+" z=1.0 interpolation=None average process create title=Segment_Annotations_Full.tif");			
			saveAs("Tiff", input + "5_Analysis_Output/Temp/AnnOut/Segment_Annotation.tif");
			close("*");
			
			HemisphereImage = CreateCmdLine(input + "5_Analysis_Output/Temp/AnnOut/Segment_Annotation.tif");		
			TransformCmd = Transformix +" -in "+HemisphereImage+" -tp "+AnnTransParam+" -out "+AnnotationImageOut;
			CreateBatFile (TransformCmd, input, "TransformixRun");
			runCmd = CreateCmdLine(input + "TransformixRun.bat");
			exec(runCmd);
			
			run("MHD/MHA...", "open=["+ input + "5_Analysis_Output/Temp/AnnOut/result.mhd]");
			setMinAndMax(0, 255);
			run("8-bit");
			run("Size...", "depth="+RegSectionsCount+" interpolation=None");
			saveAs("Tiff", input + "5_Analysis_Output/Transformed_Segments.tif");
			makePoint(AtlasSizeX/2, AtlasSizeY/2, "small yellow hybrid");
			
			
			
			// Create Segment Reference Table 
			// Then read in look-up for cross referencing value to segment name
			open(AtlasDir + "Segments.csv");
			Table.rename(Table.title, "Results");
			SegmentRefArray = newArray(nResults);
			for(i=0; i<nResults; i++) {
				SegmentRefArray[i] = getResultString("Segment", i);
			}
			close("Results");
			

			title1 = "Segment_Reference"; 
			title2 = "["+title1+"]"; 
			run("New... ", "name="+title2+" type=Table"); 
			print(title2,"\\Headings:Segment_Int"+"\tSegment"); 
			
			for(i=0; i<nSlices; i++) {
				setSlice(i+1);
				//If registration has caused a shift such than mean = 0 then it will error. If Mean =0 then mean =1
				SegMean = getValue("Mean");
				if (SegMean < 1) {
					SegMean = 1;
				}				
				print(title2,SegMean+"\t"+SegmentRefArray[SegMean-1]);	
			}
			selectWindow(title1);
			run("Text...", "save=["+ input + "5_Analysis_Output/Transformed_Segment_Annotations.csv]");
			close(title1);
			close("*");				
		}
		DeleteFile(input+"TransformixRun.bat");
		DeleteDir(input + "5_Analysis_Output/Temp/AnnOut/");
		print("   Annotation transformation complete.");
	}
		
	ProTendtime = getTime();
	dif = (ProTendtime-ProTstarttime)/1000;
	print("Transformation processing time: ", (dif/60), " minutes.");

}

function CreateDensityTableLRHemisphereFullRes(Channel, ProBGround) {
	// creates a volume and density table using a transformed annotation image
	// Transformed Annotations scaled up to match FR data
	// Isolate each region and perform density analysis
	// CreateDensityTable(input + "5_Analysis_Output/Transform_Parameters/OriginPoints/Origin_Output_Points.csv", ProCh, input + "5_Analysis_Output/Temp/Transformed_C"+ProCh+"_Binary_Out/result.mhd", input+"/5_Analysis_Output");
	//get origin front and back

	OutputDir = input+"/5_Analysis_Output";
	
	if (File.exists(OutputDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Channel+"_Measured_Projection_Density.csv")) {
		print("     Projection density analysis already performed. If you wish to rerun, delete: \n     "+OutputDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Channel+"_Measured_Projection_Density.csv");
	} else {
	
	
	if (File.exists(OutputDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron") == 0) {
		File.mkdir(OutputDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron");
	}

	// Import Raw Data - Enhanced or Ilastik depending on Analysis type

	print("   Importing projection data for density analysis...");
	
	if (ProjDetMethod == "Binary Threshold") {
		inputdir = input + "4_Processed_Sections/Enhanced/"+Channel;
		rawSections = getFileList(inputdir);
		rawSections = Array.sort( rawSections );
		Section1 = rawSections[0];
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=100 sort");
	}
	if (ProjDetMethod == "Machine Learning Segmentation with Ilastik") {
		inputdir = input + "4_Processed_Sections/Probability_Masks/"+Channel;
		rawSections = getFileList(inputdir);
		rawSections = Array.sort( rawSections );
		Section1 = rawSections[0];
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=100 sort");
		rename("Stack");
		run("Split Channels");
		selectWindow("Stack (green)");
		close("\\Others");
					
	}
	
	setAutoThreshold("Default dark stack");
	setThreshold(ProBGround, 255);
	run("Convert to Mask", "method=Default background=Dark black");
	run("Properties...", "unit=micron pixel_width="+FinalRes+" pixel_height="+FinalRes+" voxel_depth="+ZCut+"");

	// Create sagittal image at Atlas Resolution for visualization.
	print("  Creating binary dataset at "+AtlasResXY+" micron for transformation and visualization.");
	scaleX = FinalRes/AtlasResXY;
	scaleZ = ZCut/AtlasResZ;
	run("Scale...", "x="+scaleX+" y="+scaleX+" z="+scaleZ+" interpolation=None process create");
	//rename("TempScale");
	//run("Reslice [/]...", "output=25 start=Left rotate avoid");
	saveAs("Tiff",  RegDir+ "C"+Channel+"_25_Binary.tif");
	close();
	//close("TempScale");

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

	getDimensions(IMwidth, IMheight, channels, IMslices, frames);

	// Import Annotations

	print("   Importing and scaling annotation data for analysis...");
	
	open(input + "5_Analysis_Output/Transformed_Annotations.tif");
	rename("Annotations");

	// Rescale if necessary 
	run("Size...", "width="+IMwidth+" height="+IMheight+" depth="+IMslices+" interpolation=None");
	
	// Import Hemisphere Mask

	open(input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif");
	rename("Hemi_Annotations");
	
	// Rescale if necessary 
	run("Size...", "width="+IMwidth+" height="+IMheight+" depth="+IMslices+" interpolation=None");
	run("Divide...", "value=255 stack");

	// Export an image of projections and annotations for display purposes only
	selectWindow("Annotations");
	run("Scale...", "x="+ProAnRes/AtlasResXY+" y="+ProAnRes/AtlasResXY+" z=1 interpolation=None process create title=ExpAnnotations");
	if (bitDepth() == 32 ) {	

		setMinAndMax(0, 2754);
		run("glasbey on dark");
		run("16-bit");
	}
	selectWindow("ExpProjections");
	run("Scale...", "x="+ProAnRes/AtlasResXY+" y="+ProAnRes/AtlasResXY+" z=1 interpolation=None process create title=SmExp");
	setMinAndMax(0, 1);
	run("16-bit");
	run("Merge Channels...", "c1=SmExp c2=ExpAnnotations create");
	
	saveAs("Tiff",  OutputDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Channel+"_projections_with_annotation_for_display_only.tif");
	close();

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

		print("   Measuring projection density in annotated regions...");
		// multiply atlas with annotations
		selectWindow("ExpProjections");
		run("32-bit");
		imageCalculator("Multiply create stack", "ExpProjections","Annotations");
		close("ExpProjections");
		close("Annotations");
		selectWindow("Result of ExpProjections");

		//ExpVolumes = newArray(RegionIDs.length);
		ExpVolumesRight = newArray(NumIDs);
		ExpVolumesLeft = newArray(NumIDs);

					
		for (j=0; j<NumIDs; j++) {
			
			selectWindow("Result of ExpProjections");
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
		run("Text...", "save=["+  OutputDir + "/Projection_Density_Analysis_XY_"+ProAnRes+"_Z_"+ZCut+"micron/C"+Channel+"_Measured_Projection_Density.csv]");
		close(title1);
		collectGarbage(10, 4);	
		close("*");
		print("   Density measurements complete.");
	}
}


function AnnotatedRegionExtraction () {
	// Open up the full res dataset for one channel 
	// Open annotation and hemisphere annotation manipulate to match full res data
	// for each region - extract crop and save resulting file for left and right hemisphere
	// ignore dapi channel if it is at low resolution
	Exstarttime = getTime();
	print("Extracting selected regions at full resolution...");
	run("Options...", "iterations=3 count=1 black do=Nothing");
	
	OutputDir = input+"/5_Analysis_Output";
	
	if (File.exists(OutputDir + "/Full_Resolution_Extracted_Regions") == 0) {
		File.mkdir(OutputDir + "/Full_Resolution_Extracted_Regions");
	}


	//Count number of channel folders in Registered Directory
	channels = getFileList(input+ "/3_Registered_Sections/");
	ChNum = 0;
	for(i=0; i<channels.length; i++) { 
		if (File.isDirectory(input+ "/3_Registered_Sections/"+channels[i])) {
			ChNum = ChNum + 1;
		}
	}
	//Count number of registered slices
	IMslices = getFileList(input+ "/3_Registered_Sections/1/");	
	IMslices = IMslices.length;		
	

	// import data
	if (CellCh > 0) {
		Channel = CellCh;
	} else if (ProCh > 0) {
		Channel = ProCh;
	} else {
		Channel = 1;
	}
	inputdir = RegDir+Channel;
	rawSections = getFileList(inputdir);
	rawSections = Array.sort( rawSections );
	Section1 = rawSections[0];
	open(inputdir + "/" + Section1);	
	getDimensions(IMwidth, IMheight, _, _, _);
	close("");

	// Import Annotations

	print("   Importing and scaling annotation data...");
	open(input + "5_Analysis_Output/Transformed_Annotations.tif");
	rename("Annotations");
	// Rescale if necessary 
	run("Size...", "width="+IMwidth+" height="+IMheight+" depth="+IMslices+" interpolation=None");
	
	// Import Hemisphere Mask
	
	open(input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif");
	rename("Hemi_Annotations");
	
	// Rescale if necessary 
	run("Size...", "width="+IMwidth+" height="+IMheight+" depth="+IMslices+" interpolation=None");
	run("Divide...", "value=255 stack");


	// Extract each region
	ExtractRegion = num2array(ExRegionsStr,",");

	// Process each channel

	for(k=1; k<ChNum+1; k++) {	
		
	
		// import data
		inputdir = RegDir+k;
		rawSections = getFileList(inputdir);
		rawSections = Array.sort( rawSections );
		Section1 = rawSections[0];
		run("Image Sequence...", "open=["+ inputdir + "/" + Section1 + "] scale=100 sort");
		run("Properties...", "unit=micron voxel_depth="+ZCut+"");
		rename("RawData");
	
		for (j=0; j<ExtractRegion.length; j++) {
			print("    Extracting region "+ExtractRegion[j]+" in right and left hemispheres for Channel "+k+"...");

			if (File.exists(OutputDir + "/Full_Resolution_Extracted_Regions/C"+k+"_Region_"+ExtractRegion[j]+"_Right.tif")) {
				print("     Region extractoin already performed. If you wish to rerun, delete region "+ExtractRegion[j]+" files in directory: "+OutputDir + "/Full_Resolution_Extracted_Regions/");
			} else {
			
				selectWindow("Annotations");
				run("Duplicate...", "title=Annotations-Sub duplicate");
				selectWindow("Annotations-Sub");
				setThreshold(ExtractRegion[j], ExtractRegion[j]);
				run("Convert to Mask", "method=Default background=Dark black");
				run("Divide...", "value=255 stack");
				
				//Extract Right side
				imageCalculator("Multiply create stack", "Annotations-Sub","Hemi_Annotations");
				selectWindow("Result of Annotations-Sub");		
				rename("Right");
				run("16-bit");
				imageCalculator("Multiply create stack", "Right","RawData");
				close("Result of Annotations-Sub");	
				close("Right");
				
				selectWindow("Result of Right");	
	
				//crop XY
				run("Z Project...", "projection=[Max Intensity]");
				setThreshold(1, 65535);
				run("Convert to Mask");
				run("Analyze Particles...", "add");
				close("MAX_Result of Right");
				selectWindow("Result of Right");
				if (roiManager("count") == 0) {
					print("     Channel "+k+" in right hemisphere not found.");
				} else {
					roiManager("Select", 0);
					run("Crop");
					roiManager("Delete");
					cleanupROI();
			
					//crop Z
					slice = 1;		
					for (sl=1; sl<=IMslices; sl++) { 
					    setSlice(slice);
					    getRawStatistics(n, mean, min, max, std, hist); 
						if (mean == 0) {
							run("Delete Slice");
						} else {
							 slice ++;
						}
					}
					    
					// Save
					saveAs("Tiff",  OutputDir + "/Full_Resolution_Extracted_Regions/C"+k+"_Region_"+ExtractRegion[j]+"_Right.tif");
					print("     Channel "+k+" in right hemisphere has been extracted.");
				}
				close();
	
				//Extract Left side	
				imageCalculator("Subtract create stack", "Annotations-Sub","Hemi_Annotations");
				selectWindow("Result of Annotations-Sub");		
				rename("Left");
				run("16-bit");
				imageCalculator("Multiply create stack", "Left","RawData");
				close("Result of Annotations-Sub");	
				close("Left");
				selectWindow("Result of Left");	
				
				//crop XY
				run("Z Project...", "projection=[Max Intensity]");
				setThreshold(1, 65535);
				run("Convert to Mask");
				run("Analyze Particles...", "add");
				close("MAX_Result of Left");
				selectWindow("Result of Left");
				if (roiManager("count") == 0) {
					print("     Channel "+k+" in left hemisphere not found.");
				} else {
					roiManager("Select", 0);
					run("Crop");
					roiManager("Delete");
					cleanupROI();
					
					
					//crop Z
					slice = 1;		
					for (sl=1; sl<=IMslices; sl++) { 
					    setSlice(slice);
					    getRawStatistics(n, mean, min, max, std, hist); 
						if (mean == 0) {
							run("Delete Slice");
						} else {
							 slice ++;
						}
					}
					
					// Save
					saveAs("Tiff",  OutputDir + "/Full_Resolution_Extracted_Regions/C"+k+"_Region_"+ExtractRegion[j]+"_Left.tif");
					print("     Channel 2 "+k+" in left hemisphere has been extracted.");
				}
				close();
				close("Annotations-Sub");	
				close("RawData");	
			}	
		}
		
	}
	close("*");
	collectGarbage(10, 4);
	collectGarbage(10, 4);	
	print("Region extraction complete.");
	Exendtime = getTime();
	dif = (Exendtime-Exstarttime)/1000;
	print("Region extraction complete. Processing time:", (dif/60), " minutes.");
}

function FinalCleanup() {
	close("Results");
	DeleteDir(input + "5_Analysis_Output/Temp/Transformed_Raw_Out/");
	DeleteDir(input + "5_Analysis_Output/Temp/InvOut/");
	DeleteDir(input + "5_Analysis_Output/Temp/AnnOut/");
	DeleteDir(input + "5_Analysis_Output/Temp/");
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


function ResliceSagittalCoronal () {
// reslices a sagittal image to coronal, or vice versa
	rename("Image");
	run("Reslice [/]...", " start=Left rotate");
	close("Image");
	selectWindow("Reslice of Image");
}
function CountFolders(dir) {
	channels = getFileList(dir);
	ChNum = 0;
	for(i=0; i<channels.length; i++) { 
		if (File.isDirectory(dir+channels[i])) {
			ChNum = ChNum + 1;
		}
	}
	return ChNum;
}

function SCTableCounter (Region, Segment, Hemisphere, TableName) {

	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");
	if (Region > 0) {
		ResultRow = LocateID(RegionIDs, Region);
		
		for (k=0; k<SegmentArray.length; k++){	
			if(SegmentArray[k] == Segment) {
				if (Hemisphere == "Left") {
					Current = parseInt(Table.get(SegmentArray[k]+"_L", ResultRow, TableName));
					Value = Current + 1;
					Table.set(SegmentArray[k]+"_L", ResultRow, Value, TableName);
				} else {
					Current = parseInt(Table.get(SegmentArray[k]+"_R", ResultRow, TableName));
					Value = Current + 1;
					Table.set(SegmentArray[k]+"_R", ResultRow, Value, TableName);
				}
			}
		}
	}
}


function SCVolumeMeasure (Region, Segment, Hemisphere, IntVolume, TableName) {

	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");
	if (Region > 0) {
		ResultRow = LocateID(RegionIDs, Region);		
		for (k=0; k<SegmentArray.length; k++){	
			if(SegmentArray[k] == Segment) {
				if (Hemisphere == "Left") {
					Current = parseInt(Table.get(SegmentArray[k]+"_L", ResultRow, TableName));
					Value = Current+IntVolume;
					Table.set(SegmentArray[k]+"_L", ResultRow, Value, TableName);
				} else {
					Current = parseInt(Table.get(SegmentArray[k]+"_R", ResultRow, TableName));
					Value = Current + IntVolume;
					Table.set(SegmentArray[k]+"_R", ResultRow, Value, TableName);
				}
			}
		}
	}
}

function CreateEmptySpinalCordTable(tableout) {


	// Open annotation table
	OpenAsHiddenResults(AtlasDir + "Atlas_Regions.csv");		
	NumIDs = (nResults);
	RegionIDs = newArray(NumIDs);
	RegionNames = newArray(NumIDs);
	RegionAcronyms = newArray(NumIDs);
	ParentIDs = newArray(NumIDs);
	ParentAcronyms = newArray(NumIDs);
	
	for(i=0; i<NumIDs; i++) {
		RegionIDs[i] = getResult("id", i);
		RegionNames[i] = getResultString("name", i);
		RegionAcronyms[i] = getResultString("acronym", i);
		ParentIDs[i] = getResult("parent_ID", i);
		ParentAcronyms[i] = getResultString("parent_acronym", i);	
	}
	close("Results");
	
	title1 = "Annotated_Summary"; 
	title2 = "["+title1+"]";  
	run("New... ", "name="+title2+" type=Table"); 
	print(title2,"\\Headings:C1_R\tC1_L\tC2_R\tC2_L\tC3_R\tC3_L\tC4_R\tC4_L\tC5_R\tC5_L\tC6_R\tC6_L\tC7_R\tC7_L\tC8_R\tC8_L\tT1_R\tT1_L\tT2_R\tT2_L\tT3_R\tT3_L\tT4_R\tT4_L\tT5_R\tT5_L\tT6_R\tT6_L\tT7_R\tT7_L\tT8_R\tT8_L\tT9_R\tT9_L\tT10_R\tT10_L\tT11_R\tT11_L\tT12_R\tT12_L\tT13_R\tT13_L\tL1_R\tL1_L\tL2_R\tL2_L\tL3_R\tL3_L\tL4_R\tL4_L\tL5_R\tL5_L\tL6_R\tL6_L\tS1_R\tS1_L\tS2_R\tS2_L\tS3_R\tS3_L\tS4_R\tS4_L\tCo1_R\tCo1_L\tCo2_R\tCo2_L\tCo3_R\tCo3_L\tRegion_R\tRegion_L\tRegion_Total\tRegion_ID\tRegion_Acronym\tRegion_Name\tParent_ID\tParent_Acronym"); 
	
	// print each line into table 
	for(i=0; i<RegionNames.length; i++){ 
		print(title2,0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+0+"\t"+RegionIDs[i]+"\t"+RegionAcronyms[i]+"\t"+RegionNames[i]+"\t"+ParentIDs[i]+"\t"+ParentAcronyms[i]);
	} 
	run("Text...", "save=["+ tableout+ "]");
	close("Annotated_Summary");

}

function OpenAsHiddenResults(table) {			
	open(table);
	Table.rename(Table.title, "Results");
	selectWindow("Results");
	selectWindow("Log");
	selectWindow("Results");
	setLocation(screenWidth, screenHeight);
}
function SpinalCordCreateDivisionTable (Table1, Table2, Table3, TableName) {
	// Table 1 is Numerator, Table 2 Denominator, Table 3 Results
	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");	
	// Open volume and total intensity tables
	open(Table1);
	Table.rename(Table.title, "T1");
	setLocation(screenWidth, screenHeight);
	open(Table2);
	setLocation(screenWidth, screenHeight);
	Table.rename(Table.title, "T2");
	OpenAsHiddenResults(Table3);
	setLocation(screenWidth, screenHeight);

	for (i = 0; i < nResults; i++) {
		
		// Calculate Segments
		for (k=0; k<SegmentArray.length; k++){
			//Process Left Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_L", i, "T1"));
			Vol = parseInt(Table.get(SegmentArray[k]+"_L", i, "T2"));
			if (Vol > 0) {
				Value = Int/Vol;
				Table.set(SegmentArray[k]+"_L", i, Value, "Results");
			}
			//Process Right Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_R", i, "T1"));
			Vol = parseInt(Table.get(SegmentArray[k]+"_R", i, "T2"));
			if (Vol > 0) {
				Value = Int/Vol;
				Table.set(SegmentArray[k]+"_R", i, Value, "Results");
			}
		}
		
		// Calculate mean totals
		IntTotL = 0;
		VolTotL = 0;
		IntTotR = 0;
		VolTotR = 0;
		for (k=0; k<SegmentArray.length; k++){
			//Process Left Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_L", i, "T1"));
			IntTotL = IntTotL+Int;
			Vol = parseInt(Table.get(SegmentArray[k]+"_L", i, "T2"));
			VolTotL = VolTotL+Vol;
			//Process Right Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_R", i, "T1"));
			IntTotR = IntTotR+Int;
			Vol = parseInt(Table.get(SegmentArray[k]+"_R", i, "T2"));
			VolTotR = VolTotR+Vol;
			//Set the mean totals
		}
		if (VolTotR > 0) {
			Value = IntTotR/VolTotR;
			Table.set("Region_R", i, Value, "Results");
		}
		if (VolTotL > 0) { 
			Value =IntTotL/VolTotL;
			Table.set("Region_L", i, Value, "Results");
		}
		if (VolTotL+VolTotR > 0 ) {
			Value = (IntTotL+IntTotR)/(VolTotL+VolTotR);
			Table.set("Region_Total", i, Value, "Results");
		}
		
	}
	selectWindow("Results");
	run("Text...", "save=["+ Table3 +"]");
	close("T1");
	close("T2");
	close(TableName);
}


function SpinalCordCreateTotals (Table1, TableName) {
	// Table 1 is Numerator, Table 2 Denominator, Table 3 Results
	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");	
	// Open volume and total intensity tables
	OpenAsHiddenResults(Table1);
	
	for (i = 0; i < nResults; i++) {

		VolTotL = 0;
		VolTotR = 0;
		for (k=0; k<SegmentArray.length; k++){
			//Process Left Segments	
			Vol = parseInt(Table.get(SegmentArray[k]+"_L", i, "Results"));
			VolTotL = VolTotL+Vol;
			//Process Right Segments			
			Vol = parseInt(Table.get(SegmentArray[k]+"_R", i, "Results"));
			VolTotR = VolTotR+Vol;
			//Set the mean totals
		}
		Table.set("Region_R", i, VolTotR, "Results");
		Table.set("Region_L", i, VolTotL, "Results");
		Value = VolTotL+VolTotR;
		Table.set("Region_Total", i, Value, "Results");
	}
	selectWindow("Results");
	run("Text...", "save=["+ Table1 +"]");
	close(TableName);
}

function SpinalCordCreateRelativeDensityTable (Table1, Table2, TableName) {
	
	
	// Table 1 is Numerator, Table 2 Denominator, Table 3 Results
	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");	
	// Open volume and total intensity tables
	open(Table1);
	Table.rename(Table.title, "T1");
	setLocation(screenWidth, screenHeight);
	OpenAsHiddenResults(Table2);

	
	RegionIDs = newArray(nResults);
	for(i=0; i<NumIDs; i++) {
		RegionIDs[i] = getResult("Region_ID", i);
	}

	//Get total projection volume
	SumRow = LocateID(RegionIDs, 250);
	VolTot = parseInt(Table.get("Region_Total", SumRow, "T1"));
	
	// Use this to create a relative density table
	for (i = 0; i < nResults; i++) {	
		// Calculate Segments
		for (k=0; k<SegmentArray.length; k++){
			//Process Left Segments
			Vol = parseInt(Table.get(SegmentArray[k]+"_L", i, "T1"));
			if (Vol > 0) {
				Value = Vol/VolTot*100;
				Table.set(SegmentArray[k]+"_L", i, Value, "Results");
			}
			//Process Right Segments
			Vol = parseInt(Table.get(SegmentArray[k]+"_R", i, "T1"));
			if (Vol > 0) {
				Value = Vol/VolTot*100;
				Table.set(SegmentArray[k]+"_R", i, Value, "Results");
			}
		}
		// caclulate left, right and total
		Vol = parseInt(Table.get("Region_R", i, "T1"));
		if (Vol > 0) {
			Value = Vol/VolTot*100;
			Table.set("Region_R", i, Value, "Results");
		}
		Vol = parseInt(Table.get("Region_L", i, "T1"));
		if (Vol > 0) {
			Value = Vol/VolTot*100;
			Table.set("Region_L", i, Value, "Results");
		}
		Vol = parseInt(Table.get("Region_Total", i, "T1"));
		if (Vol > 0) {
			Value = Vol/VolTot*100;
			Table.set("Region_Total", i, Value, "Results");
		}
	}
	selectWindow("Results");
	run("Text...", "save=["+ Table2 +"]");
	close("T1");
	close(TableName);
}


function SpinalCordCreateDensityTable (Table1, Table2, Table3, TableName) {
	// Table 1 is Numerator, Table 2 Denominator, Table 3 Results
	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");	
	// Open volume and total intensity tables
	open(Table1);
	Table.rename(Table.title, "T1");
	setLocation(screenWidth, screenHeight);
	open(Table2);
	setLocation(screenWidth, screenHeight);
	Table.rename(Table.title, "T2");
	OpenAsHiddenResults(Table3);
	

	for (i = 0; i < nResults; i++) {
		
		// Calculate Segments
		for (k=0; k<SegmentArray.length; k++){
			//Process Left Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_L", i, "T1"));
			Vol = parseInt(Table.get(SegmentArray[k]+"_L", i, "T2"));
			if (Vol > 0) {
				Value = Int/Vol*100;
				Table.set(SegmentArray[k]+"_L", i, Value, "Results");
			}
			//Process Right Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_R", i, "T1"));
			Vol = parseInt(Table.get(SegmentArray[k]+"_R", i, "T2"));
			if (Vol > 0) {
				Value =  Int/Vol*100;
				Table.set(SegmentArray[k]+"_R", i, Value, "Results");
			}
		}
		
		// Calculate mean totals
		IntTotL = 0;
		VolTotL = 0;
		IntTotR = 0;
		VolTotR = 0;
		for (k=0; k<SegmentArray.length; k++){
			//Process Left Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_L", i, "T1"));
			IntTotL = IntTotL+Int;
			Vol = parseInt(Table.get(SegmentArray[k]+"_L", i, "T2"));
			VolTotL = VolTotL+Vol;
			//Process Right Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_R", i, "T1"));
			IntTotR = IntTotR+Int;
			Vol = parseInt(Table.get(SegmentArray[k]+"_R", i, "T2"));
			VolTotR = VolTotR+Vol;
			//Set the mean totals
		}
		if (VolTotR > 0) {
			Value = IntTotR/VolTotR*100;
			Table.set("Region_R", i, Value, "Results");
		}
		if (VolTotL > 0) { 
			Value = IntTotL/VolTotL*100;
			Table.set("Region_L", i, Value, "Results");
		}
		if (VolTotL+VolTotR > 0 ) {
			Value = (IntTotL+IntTotR)/(VolTotL+VolTotR)*100;
			Table.set("Region_Total", i, Value, "Results");
		}
		
	}
	selectWindow("Results");
	run("Text...", "save=["+ Table3 +"]");
	close("T1");
	close("T2");
	close(TableName);
}

function SpinalCordCreateCellDensityTable (Table1, Table2, Table3, TableName, mm3scale) {
	// Table 1 is Numerator, Table 2 Denominator, Table 3 Results
	SegmentArray = newArray("C1","C2","C3","C4","C5","C6","C7","C8","T1","T2","T3","T4","T5","T6","T7","T8","T9","T10","T11","T12","T13","L1","L2","L3","L4","L5","L6","S1","S2","S3","S4","Co1","Co2","Co3");	
	// Open volume and total intensity tables
	open(Table1);
	Table.rename(Table.title, "T1");
	setLocation(screenWidth, screenHeight);
	open(Table2);
	setLocation(screenWidth, screenHeight);
	Table.rename(Table.title, "T2");
	OpenAsHiddenResults(Table3);

	for (i = 0; i < nResults; i++) {

		// Calculate Segments
		for (k=0; k<SegmentArray.length; k++){
			//Process Left Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_L", i, "T1"));
			Vol = parseInt(Table.get(SegmentArray[k]+"_L", i, "T2"));
			if (Vol > 0) {
				Value = Int/Vol*mm3scale;
				Table.set(SegmentArray[k]+"_L", i, Value, "Results");
			}
			//Process Right Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_R", i, "T1"));
			Vol = parseInt(Table.get(SegmentArray[k]+"_R", i, "T2"));
			if (Vol > 0) {
				Value = Int/Vol*mm3scale;
				Table.set(SegmentArray[k]+"_R", i, Value, "Results");
			}
		}
		
		// Calculate mean totals
		IntTotL = 0;
		VolTotL = 0;
		IntTotR = 0;
		VolTotR = 0;
		for (k=0; k<SegmentArray.length; k++){
			//Process Left Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_L", i, "T1"));
			IntTotL = IntTotL+Int;
			Vol = parseInt(Table.get(SegmentArray[k]+"_L", i, "T2"));
			VolTotL = VolTotL+Vol;
			//Process Right Segments
			Int = parseInt(Table.get(SegmentArray[k]+"_R", i, "T1"));
			IntTotR = IntTotR+Int;
			Vol = parseInt(Table.get(SegmentArray[k]+"_R", i, "T2"));
			VolTotR = VolTotR+Vol;
			//Set the mean totals
		}
		if (VolTotR > 0) {
			Value = IntTotR/VolTotR*mm3scale;
			Table.set("Region_R", i, Value, "Results");
		}
		if (VolTotL > 0) { 
			Value = IntTotL/VolTotL*mm3scale;
			Table.set("Region_L", i, Value, "Results");
		}
		if (VolTotL+VolTotR > 0 ) {
			Value = (IntTotL+IntTotR)/(VolTotL+VolTotR)*mm3scale;
			Table.set("Region_Total", i, Value, "Results");
		}
		
	}
	selectWindow("Results");
	run("Text...", "save=["+ Table3 +"]");
	close("T1");
	close("T2");
	close(TableName);

}

function CreateCellDensityTableLRHemisphereFullResSpinalCord(Channel) {
	// creates a volume and cell density table using a transformed annotation image
	// Cell density expressed in mm3
	// Create region volume if necessary using Zcut thickness and lateral res provided (10um for SC, 25um for mousebrain)

	
	SCColTitles = "C1_R,C1_L,C2_R,C2_L,C3_R,C3_L,C4_R,C4_L,C5_R,C5_L,C6_R,C6_L,C7_R,C7_L,C8_R,C8_L,T1_R,T1_L,T2_R,T2_L,T3_R,T3_L,T4_R,T4_L,T5_R,T5_L,T6_R,T6_L,T7_R,T7_L,T8_R,T8_L,T9_R,T9_L,T10_R,T10_L,T11_R,T11_L,T12_R,T12_L,T13_R,T13_L,L1_R,L1_L,L2_R,L2_L,L3_R,L3_L,L4_R,L4_L,L5_R,L5_L,L6_R,L6_L,S1_R,S1_L,S2_R,S2_L,S3_R,S3_L,S4_R,S4_L,Co1_R,Co1_L,Co2_R,Co2_L,Co3_R,Co3_L,Region_R,Region_L,Region_Total,Region_ID,Region_Acronym,Region_Name,Parent_ID,Parent_Acronym\n";
	SCColTitlesList = split(SCColTitles, ",");
	
	run("Input/Output...", "jpeg=100 gif=-1 file=.csv use use_file save_column");
	OutputDir = input+"/5_Analysis_Output";

	LateralRes = 10;
	VoxSize = LateralRes*LateralRes*ZCut;
	mm3scale = parseInt(1000000000/VoxSize);
	
	if (File.exists(OutputDir + "/Cell_Analysis/C"+Channel+"_Region_and_Segment_Cell_Density_mm3.csv")) {
		print("     Cell density analysis already performed. If you wish to rerun, delete: \n     "+OutputDir + "/Cell_Analysis/C"+Channel+"_Region_and_Segment_Cell_Density_mm3.csv");
	} else {
	
		// Import Annotations - note this file is saved in XY = atlasres and Z = count of real sections
		
		print("   Importing and scaling annotation data for analysis...");
		open(input + "5_Analysis_Output/Transformed_Annotations.tif");
		rename("Annotations");
		getDimensions(width, height, channels, IMslices, frames);
	
		// Import Segments	
		open(input + "5_Analysis_Output/Transformed_Segments.tif");
		rename("Segments");
	
		// Import Hemisphere Mask
		open(input + "5_Analysis_Output/Transformed_Hemisphere_Annotations.tif");
		rename("Hemi_Annotations");
		run("Divide...", "value=255 stack");
		
		// Open annotation table		
		OpenAsHiddenResults(AtlasDir + "Atlas_Regions.csv");
		NumIDs = (nResults);
		RegionIDs = newArray(NumIDs);
		RegionNames = newArray(NumIDs);
		RegionAcronyms = newArray(NumIDs);
		ParentIDs = newArray(NumIDs);
		ParentAcronyms = newArray(NumIDs);
		ChildAcronyms = newArray(NumIDs);
		ChildIDs = newArray(NumIDs);
		
		for(i=0; i<NumIDs; i++) {
			RegionIDs[i] = getResult("id", i);
			RegionNames[i] = getResultString("name", i);
			RegionAcronyms[i] = getResultString("acronym", i);
			ParentIDs[i] = getResult("parent_ID", i);
			ParentAcronyms[i] = "\"" + getResultString("parent_acronym", i) + "\"";
			ChildAcronyms[i] = "\"" + getResultString("children_acronym", i) +"\"";
			ChildIDs[i] = "\"" + getResultString("children_IDs", i) + "\"";	
		}
		close("Results");
	
		// Then measure volume of regions in cropped annotated brain - check if it's already been measured
		SCTableOut = input+"/5_Analysis_Output/Annotated_Volumes_XY_"+LateralRes+"_Z_"+ZCut+"micron.csv";
		
		if (File.exists(SCTableOut) == false) {
			SCMeasureRegionVolumes(SCTableOut);
		} else {
			print("Annotated volumes already measured, proceeding to measure cell density");
		}


		SCCreateSummaryRows(SCTableOut);
		SCCreateSummaryRows(OutputDir + "/Cell_Analysis/C"+Channel+"_Detected_Cells_Segment_Summary.csv");
	
	// Create Empty Table
	CreateEmptySpinalCordTable(OutputDir + "/Cell_Analysis/C"+Channel+"_Region_and_Segment_Cell_Density_mm3.csv");
			
	SpinalCordCreateCellDensityTable (OutputDir + "/Cell_Analysis/C"+Channel+"_Detected_Cells_Segment_Summary.csv", input+"/5_Analysis_Output/Annotated_Volumes_XY_"+LateralRes+"_Z_"+ZCut+"micron.csv", OutputDir + "/Cell_Analysis/C"+Channel+"_Region_and_Segment_Cell_Density_mm3.csv","C"+Channel+"_Region_and_Segment_Cell_Density_mm3.csv", mm3scale);			
	print("   Cell density measurements complete.");
	}
}

function SCMeasureRegionVolumes (SCTableOut) {
	
	print("   Measuring volume of annotated regions...");
	//Create Empty Results table to add counts
	
	// 2) Open file to write into
	WriteOut = File.open(SCTableOut);

	// 3) Print headings
	print(WriteOut, "C1_R,C1_L,C2_R,C2_L,C3_R,C3_L,C4_R,C4_L,C5_R,C5_L,C6_R,C6_L,C7_R,C7_L,C8_R,C8_L,T1_R,T1_L,T2_R,T2_L,T3_R,T3_L,T4_R,T4_L,T5_R,T5_L,T6_R,T6_L,T7_R,T7_L,T8_R,T8_L,T9_R,T9_L,T10_R,T10_L,T11_R,T11_L,T12_R,T12_L,T13_R,T13_L,L1_R,L1_L,L2_R,L2_L,L3_R,L3_L,L4_R,L4_L,L5_R,L5_L,L6_R,L6_L,S1_R,S1_L,S2_R,S2_L,S3_R,S3_L,S4_R,S4_L,Co1_R,Co1_L,Co2_R,Co2_L,Co3_R,Co3_L,Region_R,Region_L,Region_Total,Region_ID,Region_Acronym,Region_Name,Parent_ID,Parent_Acronym,Children_Acronyms,Children_IDs\n");
		

	//for (j=0; j<NumIDs; j++)
	
	for (j=0; j<NumIDs; j++) {
		selectWindow("Annotations");
		run("Duplicate...", "title=Annotations-Sub duplicate");
		selectWindow("Annotations-Sub");
		setThreshold(RegionIDs[j], RegionIDs[j]);
		run("Convert to Mask", "method=Default background=Dark black");
		//Check if region actually exists - better to do before even duplicating but easist solutin for now:
		run("Z Project...", "projection=[Max Intensity]");
		Max = getValue("Max");
		close();
		//print("    ");
		if (Max > 0) {
			//print("\\Update:    Measuring volume of region "+RegionIDs[j]+" of "+NumIDs+" regions.");
			run("Divide...", "value=255 stack");
			selectWindow("Segments");
			imageCalculator("Multiply create stack", "Annotations-Sub", "Segments");
			selectWindow("Result of Annotations-Sub");	
			rename("RegionSegments");
			close("Annotations-Sub");
		
			//Create Hemispheres
			imageCalculator("Multiply create stack", "RegionSegments", "Hemi_Annotations");
			selectWindow("Result of RegionSegments");
			rename("Right");
			imageCalculator("Subtract create stack", "RegionSegments", "Right");
			selectWindow("Result of RegionSegments");		
			rename("Left");
			close("RegionSegments");
			R_Total = 0;
			L_Total = 0;
			Region_Row = "";
	
			for(k=1; k<=34; k++){
				//Measure for Right side
				volume = 0;
				selectWindow("Right");
				for (slice=1; slice<=IMslices; slice++) { 
					setSlice(slice); 
					getRawStatistics(n, mean, min, max, std, hist); 
					volume = volume + (hist[k]);    	
				}
				R_Total = R_Total + volume;
				Region_Row = Region_Row + volume + ",";
				
				//Measure for Left side
				volume = 0;
				
				selectWindow("Left");
				for (slice=1; slice<=IMslices; slice++) { 
					setSlice(slice); 
					getRawStatistics(n, mean, min, max, std, hist); 
					volume = volume + (hist[k]);    	
				}
				L_Total = L_Total + volume;
				Region_Row = Region_Row + volume + ",";
				volume = 0;
			}
		
			
			Region_Row = Region_Row + R_Total + "," + L_Total + "," + (R_Total + L_Total) + "," + RegionIDs[j] + "," + RegionAcronyms[j]+","+RegionNames[j]+","+ParentIDs[j]+","+ParentAcronyms[j]+","+ChildAcronyms[j]+","+ChildIDs[j]+"\n";					

			print(WriteOut, Region_Row);

			if (j == parseInt(NumIDs/4)) {
				print("     25% complete...");
			}
			if (j == parseInt(NumIDs/2)) {
				print("\\Update:     50% complete...");
			}
			if (j == parseInt(NumIDs/4*3)) {
				print("\\Update:     75% complete...");
			}	
			
			close("Right");
			close("Left");	
	
		} else {
			close("Annotations-Sub");
			Region_Row ="0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0," + RegionIDs[j] + "," + RegionAcronyms[j]+","+RegionNames[j]+","+ParentIDs[j]+","+ParentAcronyms[j]+","+ChildAcronyms[j]+","+ChildIDs[j]+"\n";					
			print(WriteOut, Region_Row);
		}
	}
	print("\\Update:     Measurements complete.");		
	
	// 5) Close file
	File.close(WriteOut);
	
}

function SCCreateSummaryRows (InputTable) {
	close("Results");
	//SC table column titles
	SCColTitles = "C1_R,C1_L,C2_R,C2_L,C3_R,C3_L,C4_R,C4_L,C5_R,C5_L,C6_R,C6_L,C7_R,C7_L,C8_R,C8_L,T1_R,T1_L,T2_R,T2_L,T3_R,T3_L,T4_R,T4_L,T5_R,T5_L,T6_R,T6_L,T7_R,T7_L,T8_R,T8_L,T9_R,T9_L,T10_R,T10_L,T11_R,T11_L,T12_R,T12_L,T13_R,T13_L,L1_R,L1_L,L2_R,L2_L,L3_R,L3_L,L4_R,L4_L,L5_R,L5_L,L6_R,L6_L,S1_R,S1_L,S2_R,S2_L,S3_R,S3_L,S4_R,S4_L,Co1_R,Co1_L,Co2_R,Co2_L,Co3_R,Co3_L,Region_R,Region_L,Region_Total,Region_ID,Region_Acronym,Region_Name,Parent_ID,Parent_Acronym\n";
	SCColTitlesList = split(SCColTitles, ",");

	// Open annotation table to get region and child information		
	OpenAsHiddenResults(AtlasDir + "Atlas_Regions.csv");
	NumIDs = (nResults);
	RegionIDs = newArray(NumIDs);
	RegionNames = newArray(NumIDs);
	RegionAcronyms = newArray(NumIDs);
	ParentIDs = newArray(NumIDs);
	ParentAcronyms = newArray(NumIDs);
	ChildAcronyms = newArray(NumIDs);
	ChildIDs = newArray(NumIDs);
	
	for(i=0; i<NumIDs; i++) {
		RegionIDs[i] = getResult("id", i);
		RegionNames[i] = getResultString("name", i);
		RegionAcronyms[i] = getResultString("acronym", i);
		ParentIDs[i] = getResult("parent_ID", i);
		ParentAcronyms[i] = "\"" + getResultString("parent_acronym", i) + "\"";
		ChildAcronyms[i] = "\"" + getResultString("children_acronym", i) +"\"";
		ChildIDs[i] = "\"" + getResultString("children_IDs", i) + "\"";	
	}
	close("Results");

	// Open File - Sum up all regions for each segment/side - save in SC total Row ID 250
		
	OpenAsHiddenResults(InputTable);
		
	// For each column to be summed - sum the column and save to row ID 250
	SumRow = LocateID(RegionIDs, 250);
	// Make sure table hasn't already been summed - if value of Region total in ID 250 is > 0 then skip below
	SumRowCheck = parseInt(getResult("Region_Total", SumRow));
	if (SumRowCheck == 0 ) {
	
		for (j=0; j<71; j++) {
			col = SCColTitlesList[j];			
			col_total = 0;
			for (k=0; k<NumIDs; k++) {
				col_total = col_total + getResult(col, k);
			}
			setResult(col, SumRow, col_total);		
		}
			
		// Create Summaries - For each row/region that is comprised of multiple regions:
			// Confirm Region has children
			// Sum the existing value with all of it's children's values for each column and update

		for (j=0; j<NumIDs; j++) {
			//have to remove an quotations
			Children = replace(ChildIDs[j], "\"", "");
			Children = split(Children, ",");
			if (lengthOf(Children) > 0) {
				if (Children[0] > 0) {
					for (k=0; k<71; k++) {
						col = SCColTitlesList[k];				
						col_total = getResult(col, j);
						for (l=0; l<lengthOf(Children); l++) {
							ChildRow = LocateID(RegionIDs, Children[l]); 
							col_total = col_total + getResult(col, ChildRow);
						}		
						setResult(col, j, col_total);
					}
				}
			}
		}
		
		run("Text...", "save=["+ InputTable +"]");
		close("Results");
		print("     Measurement summaries complete for "+InputTable+".");	
	} else {
		print("     Measurement summaries already performed for "+InputTable+".");
	}
}

function CheckAnnotationFile() {
	OpenAsHiddenResults(AtlasDir + "Atlas_Regions.csv");
	TableHeadings = Table.headings;
	Headlength = lengthOf(TableHeadings);
	if (Headlength <= 80) {
		print("Download updated Atlas_Regions.csv at:");
		print("https://www.dropbox.com/s/59gpbr97wbx3ki6/Atlas_Regions.csv?dl=0");
		exit("Download updated Atlas_Regions.csv via Dropbox link in Log.");
	}
}
