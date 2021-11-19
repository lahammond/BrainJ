// Reformat Sections Tool
 
// Author: 	Luke Hammond (lh2881@columbia.edu)
// Cellular Imaging | Zuckerman Institute, Columbia University
// Date:	21st November 2017
//

//	MIT License

//	Copyright (c) 2017 Luke Hammond lh2881@columbia.edu

//	Permission is hereby granted, free of charge, to any person obtaining a copy
//	of this software and associated documentation files (the "Software"), to deal
//	in the Software without restriction, including without limitation the rights
//	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//	copies of the Software, and to permit persons to whom the Software is
//	furnished to do so, subject to the following conditions:

//	The above copyright notice and this permission notice shall be included in all
//	copies or substantial portions of the Software.

//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//	SOFTWARE.


//This script reformats, centers and aligns serial tissue sections in preparation for visualization, registration and analysis."
//Image files should be stored as file sequences in folders. It is possible to batch process multiple samples/folders. <br><br> "
//Processed images will be placed into a subdirectories called 1_Reformated_Sections and 2_Section_Preview. <br> <br> "
//Image coordinates can be extracted from Nikon ND2 files for automated reordering of sections, otherwise alphanumeric filenames can be used. <br> <br> "


BrainJVer ="BrainJ 1.0.4";
ReleaseDate= "November 17, 2021";

// Initialization
requires("1.52p");
run("Options...", "iterations=1 count=1 edm=Overwrite");
run("Set Measurements...", "fit redirect=None decimal=3");
run("Colors...", "foreground=white background=black selection=yellow");
run("Clear Results"); 
run("Close All");

// Select input directories

#@ File[] listOfPaths(label="select files or folders", style="both")
//#@ boolean(label="Use GPU-acceleration (requires CLIJ)?", value = false, description="") GPU_ON

GPU_ON = false

print("\\Clear");
print(BrainJVer + " ("+ReleaseDate+") - Created by Luke Hammond. Contact: lh2881@columbia.edu");
print("Cellular Imaging | Zuckerman Institute, Columbia University - https://www.cellularimaging.org/blog/brainj");

print("Reformatting sections...");
setBatchMode(true);

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

SPreview = true;
RegRes = 20;
// Troubleshooting
DeleteWorkingFiles = false;

// Start processing folders:
print("  "+listOfPaths.length+" folders selected for processing.");

for (FolderNum=0; FolderNum<listOfPaths.length; FolderNum++) {
	inputdir=listOfPaths[FolderNum];
	if (File.exists(inputdir)) {
    	if (File.isDirectory(inputdir) == 0) {
        	print(inputdir + "Is a file, please select only directories containing brain datasets.");
        } else {
        	
        	// Process Folder:
        	
        	starttime = getTime();
        	input = inputdir + "/";
        	
        	print("  Processing folder "+FolderNum+1+": " + inputdir + " ");
       		if (File.exists(inputdir + "/Experiment_Parameters.csv")) {
	      		ParamFile = File.openAsString(inputdir + "/Experiment_Parameters.csv");
	   			ParamFileRows = split(ParamFile, "\n"); 		
	     	} else {
	       		exit("Experiment Parameter file doesn't exist, please run Setup Experiment Parameters step for this folder first.");
		   	}
       		
       		// Get Variables for running Reformt Series
    		      		     		
			SType = LocateValue(ParamFileRows, "Sample Type");
			Rotate = LocateValue(ParamFileRows, "Rotation");
			Flip = LocateValue(ParamFileRows, "Flip");
			SectionArrangement = LocateValue(ParamFileRows, "Slice Arrangement");
			FinalRes = parseFloat(LocateValue(ParamFileRows, "Final Resolution"));
			AlignCh = parseInt(LocateValue(ParamFileRows, "DAPI/Autofluorescence channel"));
			BGround = parseInt(LocateValue(ParamFileRows, "Background intensity"));
			FileOrdering = LocateValue(ParamFileRows, "File Ordering");
			ImageType = LocateValue(ParamFileRows, "Input Image Type");
			AnalysisType = LocateValue(ParamFileRows, "Analysis Type");
			InputRes = parseFloat(LocateValue(ParamFileRows, "Input Resolution"));
			AutoSeg = parseFloat(LocateValue(ParamFileRows, "Automatic Segmentation"));
			ZCut = parseInt(LocateValue(ParamFileRows, "Section cut thickness"));

			// Caution for previous versions of BrainJ
			if (InputRes == 0) {
				exit("Experiment parameters created using an earlier version of BrainJ.\n \nPlease re-run step 1: Set Experiment Parameters, for this brain.");
			}

			//RegionNumbers = getResultString("Value", 12);
			//AtlasDir = getResultString("Value", 13);
			
			FFormat = ".TIF";

			// Update Log
			print("  Sample: "+ SType + ". Image type: "+ ImageType +  ". Analysis: "+AnalysisType+".");
			print("  Input resolution: "+InputRes+"um/px. Final resolution: "+ FinalRes +"um/px.Channel selected for alignment: "+ AlignCh +". Alignment channel background: "+BGround+".");
			print("  Rotation: "+ Rotate + ". Flip: "+ Flip +".");
			PrintSectionOrder();
			
			print("");

			

			// Go through metadata and find largest Canvas size required. then pad with a percentage
			print("  Determining largest image dimensions...");
			CanvasDim = LargestCanvas(input);
			
			if (AnalysisType == "Isolated Region") {									
				CanvasWidth = parseInt(CanvasDim[0])+ 100;
				CanvasHeight = parseInt(CanvasDim[1])+ 100;
			} else {
				CanvasWidth = parseInt(CanvasDim[0])+ parseInt(CanvasDim[0]/10);
				CanvasHeight = parseInt(CanvasDim[1])+ parseInt(CanvasDim[1]/10);
				//if (Rotate != "No rotation") {
				//	CanvasWidth = parseInt(CanvasDim[1])+ parseInt(CanvasDim[1]/10);
				//	CanvasHeight = parseInt(CanvasDim[0])+ parseInt(CanvasDim[0]/10);
				//}
			}

			print("");
			print("  Largest canvas required = "+CanvasWidth+" x "+CanvasHeight+". ");
		
			//Reformat Series
			ReformatSeries(input, FinalRes);

			// Collect Garbage and check time for reformatting
			collectGarbage(10, 3);
			midendtime = getTime();

			// Rename files according to Section number
			ChanFolders = getFileList(input +"/1_Reformatted_Sections");	
			ChanFolders = Array.sort( ChanFolders );
			
			//iterate over all folders
			for(Fx=0; Fx<ChanFolders.length; Fx++) {
				ChanFolderPath = input + "/1_Reformatted_Sections/"+ChanFolders[Fx];
				ImageFiles = getFileList(ChanFolderPath);	
				ImageFiles = Array.sort( ImageFiles );
				ImageFileCounter = 1000;
			
				//iterate over all files
				for(Ix=0; Ix<ImageFiles.length; Ix++) {
					ImageFileCounter = ImageFileCounter + 1;
					a = File.rename(ChanFolderPath + ImageFiles[Ix], ChanFolderPath + "Section"+ImageFileCounter+".tif");
				}
			}
			// If analysis type regions - create the region template and Mask
			
			//if (AnalysisType == "Isolated Region/s") {
			//	print("\\Update15:Creating region mask and region specific template.");
			//	File.mkdir(input + "Region_Template_and_Mask");	
			//	CanvasDimx = CreateIsolatedTemplateRegion(RegionNumbers, AtlasDir, input + "Region_Template_and_Mask");
			//	print("\\Update16:  Complete!");
			//}
									
			// Run Slice Preview
			CreateSectionPreview(input + "1_Reformatted_Sections/", FinalRes);

			// Make folder for Ilastik_Projects
			File.mkdir(input + "Ilastik_Projects");
				
			// Get time and print Log
			endtime = getTime();
			dif = (endtime-midendtime)/1000;
			print("  Section preview montage complete. Generation time =", (dif/60), "minutes");						
			print("");
			print("Reformatting sections complete.");
			print("- - -");
			//add in some errprint("");	
			if (SType == "Mouse Brain: Coronal Sections") {
				if (CanvasWidth > 18000* InputRes || CanvasHeight > 18000* InputRes) {
					print("*Some image dimensions larger than expected - check image dimensions of specific files below.");
					print("Remove any double sections or unexpected images that could cause errors later.");
				} else if (CanvasWidth < 5000* InputRes || CanvasHeight < 5000* InputRes) {
					print("*Some image dimensions smaller than expected - check image dimensions of all files below.");
					print("Remove any images that might not contain brain section images and could cause errors later.");
				} else {
					print("All image dimensions within expected range. No issues expected but image dimensions");
					print("have been listed below in case they are required for troubleshooting:");
				}
			}
			print("");
			print(CanvasDim[3]);
			print("");
			print("Processed with "+BrainJVer + " ("+ReleaseDate+")");
			print("Created by Luke Hammond. Contact: lh2881@columbia.edu");
			print("Cellular Imaging | Zuckerman Institute, Columbia University");
			print("https://www.cellularimaging.org/blog/brainj");
			print("Available for use/modification/sharing under the MIT License: https://opensource.org/licenses/MIT");
			print("");
	
			selectWindow("Log");
			// time stamp log to prevent overwriting.
			getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
			saveAs("txt", input+"/Reformat_Sections_Log_" + year + "-" + month + "-" + dayOfMonth + "_" + hour + "-" + minute + ".txt");
        }
	}
	
}

function ReformatSeries(input, FinalRes) {
	//run by : ReformatSeries(input, FinalRes);		

	run("Collect Garbage");
	
	files = getFileList(input);	
	files = ImageFilesOnlyArray(files);		
	files = Array.sort( files );

	// Create folders:
	
	File.mkdir(input + "1_Reformatted_Sections");
	ReformatOut = input + "1_Reformatted_Sections/";
	
	// Minimum object detection size for tissue detection. 8,000,000 works well for mouse brain, 2,500,000 for mouse spinal cord (area in um).
	if (SType == "Mouse Brain: Coronal Sections") {
				DetectSz = (8000000); // was DetectSz = (8000000);
				}
	if (SType == "Mouse Brain: Sagittal Sections") {
				DetectSz = (8000000); //???? CHECK This
				}
	if(SType == "Mouse Spinal Cord") {
				DetectSz = (500000); // was 3500000
				}
	if(SType == "Smaller Sample") {
				DetectSz = (60000);
				}
	
			
	//If Reformat already run - clean up folders and notify user that old data was deleted:

	FCheck = getFileList(ReformatOut);
	if (FCheck.length > 0) {
		print("  Images from a previous run of Reformat Sections found, these have been removed. ");
		print("");
		for (f=0; f<FCheck.length; f++){
			DeleteDir(ReformatOut + FCheck[f]);
		}
	}
	
	//Create Export Subfolders
	//sample = files[0];
	//run("Bio-Formats Importer", "open=[" + input + sample + "] autoscale color_mode=Default view=Hyperstack stack_order=XYCZT");
	//getDimensions(width, height, ChNum, slices, frames);
	
	ChArray = NumberedArray(CanvasDim[2]);
	
	for(j=1; j<=ChArray.length; j++) {
			File.mkdir(input + "1_Reformatted_Sections/"+j);
	}

	run("Collect Garbage");
	
	if(FinalRes > 0) {
		Rescale = InputRes/FinalRes;
	} else {
		Rescale = 1;
	}

	//iterate over all files

	for(i=0; i<files.length; i++) {				
		image = files[i];	
		print("\\Update16:  Processing section " + (i+1) +" of " + files.length +"...");
		//Sectiontimer
		if (i == 0) {
				Sectionstart = getTime();
		}
		// import image	
		run("Bio-Formats Importer", "open=[" + input + image + "] autoscale color_mode=Default view=Hyperstack stack_order=XYCZT series_1");
		rawfilename =  getTitle();
		
		if (ImageType == "Z-Stack" ) {
			rename("3DImage");
			run("Z Project...", "projection=[Max Intensity]");
			close("3DImage");
			selectWindow("MAX_3DImage");		
		}
		
		getPixelSize(unit, W, H);
		getDimensions(width, height, ChNum, slices, frames);		

		// Correct for any resolution variability
				
		//if (W != InputRes) {
		//	print("\\Update14:**Note: Resolution not stored in metadata or all of the images may not be at the same resolution.");
		//	print("\\Update15:for consistency the input resolution provided was used for all images.");
		//	print("\\Update16: This is not necessarily a problem. To confirm image resolution check image scaling in ImageJ by Image>Properties.");
		//}
		
		run("Properties...", "unit=micron pixel_width="+InputRes+" pixel_height="+InputRes+" voxel_depth="+ZCut);	
		
		//Rescale Image
		if(FinalRes > 0) {
			RescaleImage(Rescale);
		} else {
			FinalRes = InputRes;
		}
		
		//rotate and flip as required
		if(Rotate == "Rotate 90 degrees right") {
			run("Rotate 90 Degrees Right", "stack");
		}
		if(Rotate == "Rotate 90 degrees left") {
			run("Rotate 90 Degrees Left", "stack");
		}
		
		if(Flip == "Flip Vertically")	{
			run("Flip Vertically", "stack");
		}
		if(Flip == "Flip Horizontally")	{
			run("Flip Horizontally", "stack");
		}
		// rename with coordinate
		
		if (FileOrdering == "Nikon ND2 stage coodinates"){ 
			XY_Title = GenCoordinateName();
		}
		if (FileOrdering == "Alphanumeric"){ 
			XY_Title = short_title(image);
		}
		
		rename("Raw");
		
		//getPixelSize(unit, pW, pH);
		
		// pW = XY = InputRes;
		
		// Adjust variables according to tissue type
		
		ScUpXY = RegRes/FinalRes;
		ScDnXY = FinalRes/RegRes;
		
		cleanupROI();
	
		//Modify Canvas to match rescale
		if(Rotate == "Rotate 90 degrees right" || Rotate == "Rotate 90 degrees left") {
			NewCanvasWidth = parseInt((Rescale*CanvasHeight));
			NewCanvasHeight = parseInt((Rescale*CanvasWidth));
		} else {
			NewCanvasWidth = parseInt((Rescale*CanvasWidth));
			NewCanvasHeight = parseInt((Rescale*CanvasHeight));
		}
		
		run("Canvas Size...", "width="+NewCanvasWidth+" height="+NewCanvasHeight+" position=Center zero");
					
		if (ChNum > 1) {
				run("Split Channels");
				selectWindow("C" + AlignCh + "-Raw");
		} else {
			rename("C1-Raw");
		}

		if (AnalysisType == "Isolated Region") {


			// Save each channel in a folder
			for(j=1; j<=ChArray.length; j++) {
				selectWindow("C" + j + "-Raw");
				if (FFormat == ".TIF"){
					save(input + "1_Reformatted_Sections/"+j+"/" + XY_Title);
				}
				if (FFormat == ".JPEG") {
					saveAs("Jpeg", input + "1_Reformatted_Sections/"+j+"/" + XY_Title +".jpg");
				}
				close();
			}


			
		} else {
	
			run("Scale...", "x="+ScDnXY+" y="+ScDnXY+" interpolation=None average create title=RawScale");

	
			if (AutoSeg == true) {
				//Automatic Detection settings
				run("Subtract Background...", "rolling=25");
				//setThreshold(45, 65535);
				run("Auto Threshold", "method=Mean white");
				setOption("BlackBackground", true);
				run("Convert to Mask");	
				run("Median...", "radius=2");	
				//run("Fill Holes");
				run("Dilate");
				run("Dilate");
				run("Dilate");
				run("Fill Holes");		
				run("Erode");
				run("Erode");
				run("Erode");

				
			} else {
			// Subtract background value (works for most brains without this), not subtracting all background may create issues for mean threshold
			run("Subtract...", "value="+BGround+"");
			// Apply Threshold
			run("Set Measurements...", "mean fit redirect=None decimal=3");
			run("Auto Threshold", "method=Mean white");
			setOption("BlackBackground", true);
			run("Colors...", "foreground=white background=black selection=yellow");
			run("Convert to Mask"); 
			
			}		
			
			// correction for images that are inverted (sometimes occurs if user has opened and resaved Section in imageJ with different settings)
			//** this part needs to be corrected for spinal cords image size		
			checkforinversion();
			
			//fill holes in binary section
			run("Dilate");
			run("Fill Holes");
			setOption("BlackBackground", true);

			// Analyse Particles - detect ROIs if greater than 1 then merge ** detection here is in micron!				
			run("Analyze Particles...", "size="+DetectSz+"-Infinity add");		
			run("Clear Results");

		
			// Count detected ROIs and treat accordingly
			CountROIsub=0;
			CountROIsub=roiManager("count"); 
			if (CountROIsub==0) {
				print("no section detected in image "+(i+1)+". Filename: "+rawfilename);
				
			} else if (CountROIsub==1) {
				roiManager("Select", 0);
				//run("Measure");
				List.setMeasurements;
				run("Clear Outside", "stack");
				roiManager("Delete");
				run("Select None");
			} else if (CountROIsub>1) {
				ROIarraysub=newArray(CountROIsub); 
				for(m=0; m<CountROIsub;m++) { 
		    		ROIarraysub[m] = m; 
					} 
				roiManager("Select", ROIarraysub);
				roiManager("Combine");
				//run("Measure");
				List.setMeasurements;
				run("Clear Outside", "stack");
				roiManager("Delete");
				run("Select None");
				ROIarraysub=newArray(0);
			}

			//Rotation angle corrections
			if (CountROIsub > 0 ) {
				offset_angle = List.getValue("Angle"); 
			} else {
				offset_angle = 0;
			}
			//if (offset_angle > 45 && offset_angle <135) {
			if (offset_angle > 40 && offset_angle <130) {
				offset_angle = 0;			
			} 
			if (offset_angle < -130 && offset_angle > -40) {
				//offset_angle = (offset_angle - 180)*-1;
				offset_angle = 0;
			}
			if (offset_angle > 40) {
				offset_angle = (offset_angle - 180); // removed *-1
			}
		
			//run("Clear Results"); 
			run("Select None");
			//rotate threshold image
			print("\\Update16:  Processing section " + (i+1) +" of " + files.length +"... centered and rotating "+offset_angle+" degrees.");
			run("Rotate... ", "angle=offset_angle grid=20 interpolation=Bilinear fill");
			
			// scale up thresh image for true size ROI for clearing
			
			run("Scale...", "x="+ScUpXY+" y="+ScUpXY+" interpolation=Bilinear average create title=RawScaledUp");
			close("RawScale");
			selectWindow("RawScaledUp");
			run("Make Binary");
			
		
			// correction for images that are inverted (sometimes occurs if user has opened and resaved slice in imageJ with different settings)
			checkforinversion();
			//create array ChArray and rotate all channels then crop clear and expand
			
			for(j=1; j<=ChArray.length; j++) {
				selectWindow("C" + j + "-Raw");
				run("Rotate... ", "angle=offset_angle grid=20 interpolation=Bilinear fill");
					/*removed enhancement steps but this is what could be included
					 * if (Ch1USSZ > 0) {
						run("Unsharp Mask...", "radius="+Ch1USSZ+" mask="+Ch1USW+"");
						run("Subtract Background...", "rolling="+Ch1BgSZ+"");
					}
					*/
				// size is in microns - so consistant across scaling
				selectWindow("RawScaledUp");
				run("Analyze Particles...", "size="+DetectSz+"-Infinity add");
							
				CountROIsub=0;
				CountROIsub=roiManager("count"); 
				if (CountROIsub==0) {
					run("Canvas Size...", "width="+NewCanvasWidth+" height="+NewCanvasHeight+" position=Center zero");
				} else if (CountROIsub==1) {
					selectWindow("C" + j + "-Raw");
					roiManager("Select", 0);
					run("Crop");
					run("Clear Outside");
					run("Canvas Size...", "width="+NewCanvasWidth+" height="+NewCanvasHeight+" position=Center zero");
				}
				cleanupROI();	
			}
		
			close("RawScaledUp");
				
			// Final correction for any slight variations in image size (should be corrected by scaling correction)		
			if (i == 0) {
				getDimensions(FinalWidth, FinalHeight, dummy, dummy, dummy);
			} else {
				getDimensions(CurrentWidth, CurrentHeight, dummy, dummy, dummy);
				if (CurrentWidth != FinalWidth || CurrentHeight != FinalHeight) {
					run("Size...", "width="+FinalWidth+" height="+CurrentHeight+" average interpolation=Bilinear");
				}
			}	

			// remove any colormaps - can slow processing in Ilastik
			run("Grays");
			
			// Save each channel in a folder
			for(j=1; j<=ChArray.length; j++) {
				selectWindow("C" + j + "-Raw");
				if (FFormat == ".TIF"){
					save(input + "1_Reformatted_Sections/"+j+"/" + XY_Title);
				}
				if (FFormat == ".JPEG") {
					saveAs("Jpeg", input + "1_Reformatted_Sections/"+j+"/" + XY_Title +".jpg");
				}
				close();
			}
		}				
		run("Collect Garbage");

		if (i == 0) {
			Sectionend = getTime();
			Sectiontime = (Sectionend-Sectionstart)/1000;
			print("  Processing time for one section = " +parseInt(Sectiontime)+ " seconds. Total time for this brain will be ~"+(parseInt((Sectiontime*files.length)/60)), "minutes.");
			
			
		}

		run("Close All");
	}
	// timing and log	
	midendtime = getTime();
	middif = (midendtime-starttime)/1000;
	print("");
	print("Tif generation complete. Processing time =", parseInt(middif/60), "minutes. ", parseInt(middif/i), "seconds per section.");

}			
	

function CreateSectionPreview(InputFolder, FinalRes) {		
	//call using : CreateSectionPreview(input + "Export/", ChNum, FinalRes);	
	// Preparation
	print("- - -");
	print("Creating scaled down stack for checking section quality and order...");
	channeldirs = getFileList(InputFolder);
	Channels = channeldirs.length;

	//
	
		
	for(j=1; j<=Channels; j++) {
		Export = InputFolder+j+"/";
		previewfiles = getFileList(Export);
		previewfiles =Array.sort( previewfiles );
		previewimage = previewfiles[0];		
		downscale = (0.03/(1/(FinalRes)));
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
	
	
	if (Channels == 2){
		run("Merge Channels...", "c1=Raw-1 c2=Raw-2 create");
	}
	if (Channels == 3){
		run("Merge Channels...", "c1=Raw-1 c2=Raw-2 c3=Raw-3 create");
	}
	if (Channels == 4){
		run("Merge Channels...", "c1=Raw-1 c2=Raw-2 c3=Raw-3 c4=Raw-4 create");
	}

	input_ID = getImageID();

	//make montage
	run("Remove Slice Labels");	
	run("Colors...", "foreground=white background=black selection=yellow");
					
	File.mkdir(input + "2_Section_Preview");
	sq = round(sqrt(previewfiles.length));
	col = sq;
	row = (sq+1);
	run("Make Montage...", "columns="+col+" rows="+row+" scale=1 font=14 label use");
	run("Make Composite", "display=Composite");
	saveAs("Tiff", "" + input + "2_Section_Preview/Section_Preview_Montage.tif");
	close();

	// save stack preview
	selectImage(input_ID); 
	run("Re-order Hyperstack ...", "channels=[Channels (c)] slices=[Frames (t)] frames=[Slices (z)]");
	run("Time Stamper", "starting=1 interval=1 x=5 y=16 font=14 decimal=0 anti-aliased or= ");
	saveAs("Tiff", input + "2_Section_Preview/Section_Preview_Stack.tif");
	close();
	run("Collect Garbage");
}
	



function GenCoordinateName(){
	//expects a section order variable to be provided in the start menu.
	
	input_Title = getTitle();
	
	names=split(input_Title, "/");
	if (names.length > 1) {
		input_Title = names[(names.length-1)];
	}


	smTitle = substring(input_Title,0,9);
	//Elements 5.11 changed the file naming. So included this to fix:
	if(substring(input_Title,6,7) == "-"){
		casette = substring(input_Title,5,6);
		if(substring(input_Title,8,9) == "_"){
			slide511=100+parseInt(substring(input_Title,7,8));
			
		} else {
			slide511=100+parseInt(substring(input_Title,7,9));
		}
		smTitle = "Slide"+casette+slide511+"_";
			
	
	}
		//Get Metadata from Image
	XRow = 0;
	infoString=getMetadata("ND2info");
	rows=split(infoString, "\n"); 
	for(i=0; i<rows.length; i++){ 
		if(matches(rows[i],".*dXPos.*") == 1){
			XRow=i;
		}
		if(matches(rows[i],".*dYPos.*") == 1){
			YRow=i;
		}
	}

	if (XRow == 0) {
		print("Coordinate information could not be located. Please rerun using alphanumerically labelled files.")
		exit("Coordinate information could not be located. Please rerun using alphanumerically labelled files.")
	}
	
	XPos=substring(rows[XRow],8,10);
	YPos=substring(rows[YRow],8,10);
	//Read in X position line and record value. accuracy to mm sufficient
		//Pre July 2018
				//	Xinfo=indexOf(infoString,"m_dXYPositionX0");
				//XPos=substring(infoString,Xinfo+18,Xinfo+20);
		//Post July 2018
	
	//print("X Position = "+XPos);
	//Read in Y position line and record value. accuracy to mm sufficient
		//Yinfo=indexOf(infoString,"m_dXYPositionY0");
		//YPos=substring(infoString,Yinfo+18,Yinfo+20);
	
	//print("Y Position = "+YPos);

	if (SectionArrangement == "Right and Down"){
		if (YPos >=30) {
			YPos = 1;
		} else {
			YPos = 2;
		}
		XPos = round((1/XPos)*10000);
		XY_Title = smTitle + "_Y_"+ YPos +"_X_"+ XPos +".tif";
	}
	if (SectionArrangement == "Left and Down"){
		if (YPos >=30) {
			YPos = 1;
		} else {
			YPos = 2;
		}
		XY_Title = smTitle + "_Y_"+ YPos +"_X_"+ XPos +".tif";
	}
	if (SectionArrangement == "Right and Up"){
		if (YPos >=30) {
			YPos = 2;
		} else {
			YPos = 1;
		}
		XPos = round((1/XPos)*10000);
		XY_Title = smTitle + "_Y_"+ YPos +"_X_"+ XPos +".tif";
	}
	if (SectionArrangement == "Left and Up"){
		if (YPos >=30) {
			YPos = 2;
		} else {
			YPos = 1;
		}
		XY_Title = smTitle + "_Y_"+ YPos +"_X_"+ XPos +".tif";
	}
	if (SectionArrangement == "Right"){
		if (YPos >=30) {
			YPos = 1;
		} else {
			YPos = 2;
		}
		XPos = round((1/XPos)*10000);
		XY_Title = smTitle + "_X_"+ XPos +"_Y_"+ YPos +".tif";
	}
	if (SectionArrangement == "Left"){
		if (YPos >=30) {
			YPos = 1;
		} else {
			YPos = 2;
		}
		XY_Title = smTitle + "_X_"+ XPos +"_Y_"+ YPos +".tif";
	} 
	if (SectionArrangement == "Right (single row)"){
		XPos = round((1/XPos)*10000);
		XY_Title = smTitle +"_X_"+ XPos +".tif";
	}
	if (SectionArrangement == "Left (single row)"){
		XY_Title = smTitle +"_X_"+ XPos +".tif";
	}
	return XY_Title;
	
}

function PrintSectionOrder () {
	if (SectionArrangement == "Right and Down"){
		print("  Sections are being ordered according to Right and Down arrangement.");
		print("  E.g. Top: 1, 2, 3, 4 | Bottom: 5, 6, 7, 8");
	}
	if (SectionArrangement == "Left and Down"){
		print("  Sections are being ordered according to Left and Down arrangement.");
		print("  E.g. Top: 4, 3, 2, 1 | Bottom: 8, 7, 6, 5");
	}
	if (SectionArrangement == "Right and Up"){
		print("  Sections are being ordered according to Right and Up arrangement.");
		print("  E.g. Bottom: 1, 2, 3, 4 | Top: 5, 6, 7, 8");
	}
	if (SectionArrangement == "Left and Up"){
		print("  Sections are being ordered according to Left and Up arrangement.");
		print("  E.g. Bottom: 4, 3, 2, 1 | Top: 8, 7, 6, 5");
	}
	if (SectionArrangement == "Right"){
		print("  Sections are being ordered according to Right arrangment.");
		print("  E.g. Top: 1, 3, 5, 7 | Bottom: 2, 4, 6, 8. This arrangement can lead to some sections being out of step. When checking file names, order should be Y_1, then Y_2. If you see instances of Y_2 then Y_1, reduce the X_ value in the filename to correct.");
	}
	if (SectionArrangement == "Left"){
		print("  Sections are being ordered according to Left arrangement.");
		print("  E.g. Top: 7 , 5, 3, 1 | Bottom: 8, 6, 4, 2. This arrangement can lead to some sections being out of step. When checking file names, order should be Y_1, then Y_2. If you see instances of Y_2 then Y_1, reduce the X_ value in the filename to correct.");
	} 
	if (SectionArrangement == "Right (single row)"){
		print("  Sections are being ordered according to Right and Down arrangement.");
		print("  E.g. Top: 1, 2, 3, 4 | Bottom: 5, 6, 7, 8");
	}
	if (SectionArrangement == "Left (single row)"){
		print("  Sections are being ordered according to Left and Down arrangement.");
		print("  E.g. Top: 4, 3, 2, 1 | Bottom: 8, 7, 6, 5");
	}
	
}

function RescaleImage(Rescale){
	//Expects FinalRes as an input from user in menu
	input_Title = getTitle();
	input_ID = getImageID();
	//get image information		
	//getPixelSize(unit, W, H);
	// Determine rescale value
	//Rescale = (1/(FinalRes/W));
	run("Scale...", "x="+Rescale+" y="+Rescale+" interpolation=Bilinear average create");
	rescale_ID = getImageID(); 
	selectImage(input_ID);
	close();
	selectImage(rescale_ID);
	rename(input_Title);
}
function DeleteDir(Dir){
	listDir = getFileList(Dir);
  	//for (j=0; j<listDir.length; j++)
      //print(listDir[j]+": "+File.length(myDir+list[i])+"  "+File. dateLastModified(myDir+list[i]));
 // Delete the files and the directory
	for (j=0; j<listDir.length; j++)
		ok = File.delete(Dir+listDir[j]);
	ok = File.delete(Dir);
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
function ImageFilesOnlyArray (arr) {
	//pass array from getFileList through this e.g. NEWARRAY = ImageFilesOnlyArray(NEWARRAY);
	setOption("ExpandableArrays", true);
	f=0;
	files = newArray;
	for (i = 0; i < arr.length; i++) {
		if(endsWith(arr[i], ".tif") || endsWith(arr[i], ".nd2") || endsWith(arr[i], ".LSM") || endsWith(arr[i], ".czi") || endsWith(arr[i], ".jpg") ) {   //if it's a tiff image add it to the new array
			files[f] = arr[i];
			f = f+1;
		}
	}
	arr = files;
	arr = Array.sort(arr);
	return arr;
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

function checkforinversion() {
	// correction for images that are inverted (sometimes occurs if user has opened and resaved slice in imageJ with different settings)
	//** this part needs to be corrected for spinal cords image size	REMOVE?
	getDimensions(wsm, hsm, ChNumsm, slicessm, framessm);
	makeRectangle(10, 18, 23, 19);
	List.setMeasurements;
	boxint = List.getValue("Mean"); 
	if (boxint == 255) {
		run("Select None");
		run("Invert");
		run("Clear Results");
	} else {
		run("Select None");
		run("Clear Results");
	}
}

function closewindow(windowname) {
	if (isOpen(windowname)) { 
      		 selectWindow(windowname); 
       		run("Close"); 
  		} 
}

function short_title(imagename){
	nl=lengthOf(imagename);
	nl2=nl-3;
	Sub_Title=substring(imagename,0,nl2);
	Sub_Title = replace(Sub_Title, "(", "_");
	Sub_Title = replace(Sub_Title, ")", "_");
	Sub_Title = replace(Sub_Title, "-", "_");
	Sub_Title = replace(Sub_Title, "+", "_");
	Sub_Title = replace(Sub_Title, " ", "_");
	Sub_Title=Sub_Title+".tif";
	return Sub_Title;
}

function CreateIsolatedTemplateRegion (RegionNumbers, AtlasDir, OutputDir) {


	RegionArray = num2array(RegionNumbers,",");
	
	//Open template files and merge if necessary
	cleanupROI();
	
	
	if (File.exists(AtlasDir + "ABA25_Masks/structure_" +RegionArray[0]+ ".nrrd")) {
		open(AtlasDir + "ABA25_Masks/structure_" +RegionArray[0]+ ".nrrd");
	} else {
		exit("Brain Region "+RegionArray[0]+" Does Not Exist - please check ABA region number.")
	}
	rename("BrainMask");
	
	
	if (RegionArray.length > 1) {
		for (i = 1; i <= (RegionArray.length-1); i++) {
			if (File.exists(AtlasDir + "ABA25_Masks/structure_" +RegionArray[i]+ ".nrrd")) {
				open(AtlasDir + "ABA25_Masks/structure_" +RegionArray[i]+ ".nrrd");
				rename("NewMask");
				imageCalculator("Add create stack", "BrainMask","NewMask");
				closewindow("BrainMask");
				closewindow("NewMask");
				selectWindow("Result of BrainMask");
				rename("BrainMask");
	
				
			} else {
				exit("Brain Region "+RegionArray[i]+" Does Not Exist - please check ABA region number.")
			}
		}
	}
	
	// Measure sagittal location of isolated region so that we can make cubic mask
	run("Z Project...", "projection=[Max Intensity]");
	selectWindow("MAX_BrainMask");
	setThreshold(1, 255);	
	setOption("BlackBackground", true);
	run("Convert to Mask");
	run("Analyze Particles...", "add");
	roiManager("Select", 0);
	run("Properties...", "channels=1 slices=1 frames=1 unit=micron pixel_width=1 pixel_height=1 voxel_depth=1");
	run("Set Measurements...", "centroid redirect=None decimal=0");
	run("Clear Results");
	run("Measure");
	SagRegionCentroidX = parseInt(getResult("X", 0));
	SagRegionCentroidY = parseInt(getResult("Y", 0));
	
	run("Crop");
	getDimensions(Sagregionwidth, dd, dd, dd, dd);
	Sagregionwidth = parseInt(Sagregionwidth*1.5);
	closewindow("MAX_BrainMask");
	cleanupROI();
	
	// Measure template brain region width and height (coronal)
	run("Reslice [/]...", "output=25.000 start=Left flip rotate avoid");
	run("Z Project...", "projection=[Max Intensity]");
	// clear opposite hemisphere
	if (AnalysisHemisphere == "Left") {
		makeRectangle(0, 0, 228, 320);
		run("Clear Outside");
		run("Select None");
	}
	if (AnalysisHemisphere == "Right") {
		makeRectangle(229, 0, 228, 320);
		run("Clear Outside");
		run("Select None");
	}
	// Set measurements
	setThreshold(1, 255);	
	setOption("BlackBackground", true);
	run("Convert to Mask");
	run("Analyze Particles...", "add");
	roiManager("Select", 0);
	run("Properties...", "channels=1 slices=1 frames=1 unit=micron pixel_width=1 pixel_height=1 voxel_depth=1");
	run("Set Measurements...", "centroid redirect=None decimal=0");
	run("Clear Results");
	run("Measure");
	RegionCentroidX = parseInt(getResult("X", 0));
	RegionCentroidY = parseInt(getResult("Y", 0));
	run("Crop");
	run("Clear Results");
	getDimensions(regionwidth, regionheight, dd, dd, dd);
	regionwidth = parseInt(regionwidth*1.5);
	regionheight = parseInt(regionheight*1.5);
	closewindow("MAX_Reslice of BrainMask");
	closewindow("Reslice of BrainMask");
	newImage("Template_Mask", "16-bit black", 456, 320, 528);
	//Define Region for filling and correct for any out of bounds
	RegionLeftCorner = parseInt(RegionCentroidX-(regionwidth/2));
	RegionTopCorner = parseInt(RegionCentroidY-(regionheight/2));
	if (RegionLeftCorner < 0) {
		RegionLeftCorner = 0;
	}
	if (RegionTopCorner < 0) {
		RegionTopCorner = 0;
	}
	if (RegionLeftCorner+regionwidth > 456) {
		RegionLeftCorner = 456-regionwidth;
	}
	if (RegionTopCorner+regionheight > 320) {
		RegionTopCorner = 320-regionheight;
	}
	if (parseInt(SagRegionCentroidX-(Sagregionwidth/2)) < 0) {
		SagRegionCentroidX = parseInt((Sagregionwidth/2));
	}
	if (parseInt(SagRegionCentroidX+(Sagregionwidth/2)) > 528) {
		SagRegionCentroidX = 528 - parseInt((Sagregionwidth/2));
	}
	selectWindow("Template_Mask");
	for (i = 0; i <= Sagregionwidth; i++) {
		setSlice((SagRegionCentroidX-(Sagregionwidth/2))+i);
		makeRectangle(RegionLeftCorner, RegionTopCorner, regionwidth, regionheight);
		run("Fill", "slice");
	}
	run("Select None");
	run("Reslice [/]...", "output=1.000 start=Left flip rotate avoid");
	run("Flip Horizontally", "stack");
	// Save Mask Image
	saveAs("Tiff", OutputDir + "Isolated_Region_Mask.tif");
	closewindow("Isolated_Region_Mask.tif");
	closewindow("Template_Mask");
	
	
	//Create and save Isolated Region Template
	open(AtlasDir + "template_25.tif");
	rename("Template");
	imageCalculator("Multiply create stack", "BrainMask","Template");
	selectWindow("Result of BrainMask");
	saveAs("Tiff", OutputDir + "Isolated_Region_Template.tif");
	closewindow("Isolated_Region_Template.tif");
	closewindow("Template");
	closewindow("BrainMask");
	
	// Calculate Coronal Image Size for Reformat Sections
	CanvasDim = newArray(2);
	CanvasDim[0] = regionwidth*25/FinalRes;
	CanvasDim[1] = regionheight*25/FinalRes;
	
	return CanvasDim;

}

function num2array(str,delim){
	arr = split(str,delim);
	for(i=0; i<arr.length;i++) {
		arr[i] = parseInt(arr[i]);
	}

	return arr;
}

function LargestCanvas(input) {
	FinalCanvasSizeX = 0;
	FinalCanvasSizeY = 0;
	
		
	files = getFileList(input);	
	files = ImageFilesOnlyArray(files);		
	files = Array.sort( files );
	CanvasSizes = "";
	if (files.length == 0) {
		exit("No image files found in folder.");
	}
	for(i=0; i<files.length; i++) {				
			
		run("Bio-Formats Macro Extensions");
		Ext.setId(input + files[i]);
		Ext.getSizeX(CanvasSizeX);
		Ext.getSizeY(CanvasSizeY);
		if (i == 0) {
			Ext.getSizeC(TotalChannels0);
		}
		Ext.getSizeC(TotalChannels1);
		if (TotalChannels0 != TotalChannels1) {
			exit("Not all images contain the same number of channels/nCheck folder and remove any non section images (e.g. single channel prescan/slide overview images)");
		}
		Ext.close();
		
		
		
		
		
		//run("Bio-Formats Importer", "open=[" + input + image + "] color_mode=Default display_metadata rois_import=[ROI manager] view=[Metadata only] stack_order=Default");
		//selectWindow("Original Metadata - " + image );
		//saveAs( "Results", input + "temp_metadata.txt" );
		//selectWindow("Original Metadata - " + image );
		//run("Close");

		// NOTE! Was using SizeX and SizeY in Metadata- BUT if people edit the image before the 
		// pipeline then it will think the images are much bigger htan they are. So check if edited in ImageJ
		// In images opened by ImageJ there will be a line beginning Width: and Height: at end of metadata
		// Just taking first SizeX and SizeY seems to address all issues.
		
		//XFound = 0;
		//YFound = 0;
		//CFound = 0;
		
		//Metadata = split( File.openAsString( input + "temp_metadata.txt" ), "\n" );

		/*
		for(meta=0; meta<Metadata.length; meta++){ 
			if(matches(Metadata[meta],".* SizeX.*") == 1 && matches(Metadata[meta],".*VoxelSizeX.*") == 0 && XFound == 0 ) {
				SizeXRow=Metadata[meta];
				SizeXRow = split(SizeXRow, "\t");
				CanvasSizeX = (SizeXRow[1]);
				XFound = 1;
			}
						
			if(matches(Metadata[meta],".* SizeY.*") == 1 && matches(Metadata[meta],".*VoxelSizeY.*") == 0 && YFound == 0 ) {
				SizeYRow=Metadata[meta];
				SizeYRow = split(SizeYRow, "\t");
				CanvasSizeY = (SizeYRow[1]);
				YFound = 1;
			}
			if(matches(Metadata[meta],".* SizeC.*") == 1 && matches(Metadata[meta],".*VoxelSizeY.*") == 0 && CFound == 0 ) {
				SizeCRow=Metadata[meta];
				SizeCRow = split(SizeCRow, "\t");
				TotalChannels = (SizeCRow[1]);
				CFound = 1;
			}
			
		}
		*/
		if (CanvasSizeX > FinalCanvasSizeX) {
			FinalCanvasSizeX = CanvasSizeX;
		}
		if (CanvasSizeY > FinalCanvasSizeY) {
			FinalCanvasSizeY = CanvasSizeY;
		}
		
		CanvasSizes = CanvasSizes +"" +files[i]+ "  Width = " + CanvasSizeX + "  Height = " + CanvasSizeY +"\n";
	}
	
		
	CanvasDim = newArray(4);
	CanvasDim[0] = FinalCanvasSizeX;
	CanvasDim[1] = FinalCanvasSizeY;
	CanvasDim[2] = TotalChannels1;
	CanvasDim[3] = CanvasSizes;

	ok = File.delete(input + "temp_metadata.txt");

	return CanvasDim;

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

//Consider using Temp directory for server processing.
//tmp = getDirectory("temp");
//  if (tmp=="")
//      exit("No temp directory available");
//  else
//  	print(tmp);