// Setup Brain Parameters Tool

// First open input directory and check for parameter file

// if parameter file exists - populate all the variables - if not then just proceed

//Replacing Unused Options
USRad = 0;
USMW = 0;
CellDetectionResolution = 0;
IntVal = 0;

ProDetectionResolutionZ = 25;
AtlasType = "25um template brain";

//AtlasMaskLocation = "0";
//AtlasTemplateLocation = "0";

// Set Trim (default was 6 but can include too much data). Trim is how many voxels are removed from the transformed dataset to ensure to erronously morphed image data is included.
TransVolumeTrim = 15;


#@ File(label="Select folder:", description="Folder containing brain data", style="directory") input

#@ Integer(label="Reference section for registration:", value = 35, style="spinner", description="The should be a section roughly in the middle of the brain") RefSection
#@ Integer(label="Background removal prior to segmentation (rolling ball radius in px, 0 if none):", value = 7, style="spinner") BGSub
#@ boolean(label="Generate full resolution registered image of reference channel:", description="Leave off to save diskspace and time. Enable only if a full resolution image of this channel is required for cell and projection analysis.") FullResDAPI
#@ boolean(label="Perform a second pass section registration:", description="Turn on only when using fiducial markers to correct registration of badly damaged tissue sections.") SecondPass


#@String  (visibility="MESSAGE", value="------------------------------------------------------------------Cell Analysis Settings------------------------------------------------------------------") out2
#@ String(label="Method for cell detection:", choices={"No Cell Analysis", "Manual Cell Count" ,"Find Maxima", "Machine Learning Segmentation with Ilastik"}, value = "Machine Learning Segmentation with Ilastik", style="listBox", description="") CellDetType
#@ String(label="Channel for cell detection/analysis (0 for none):", choices={"1", "2", "3", "4", "0"}, style="radioButtonHorizontal", value = "1", description="Select the channel number containing DAPI or Autofluorescence, to be used for registration.") CellCh1
#@ Integer(label="Minimum intensity threshold:", value = 125, style="spinner") MaximaInt1
#@ Integer(label="Minimum cell area (um):", value = 20, style="spinner") Size1
#@ String(label="Additional channel for cell detection/analysis:", choices={"1", "2", "3", "4", "0"}, style="radioButtonHorizontal", value = "0", description="Select the channel number containing DAPI or Autofluorescence, to be used for registration.") CellCh2
#@ Integer(label="Minimum intensity threshold:", value = 125, style="spinner") MaximaInt2
#@ Integer(label="Minimum cell area (um):", value = 20, style="spinner") Size2
#@ String(label="Additional channel for cell detection/analysis:", choices={"1", "2", "3", "4", "0"}, style="radioButtonHorizontal", value = "0", description="Select the channel number containing DAPI or Autofluorescence, to be used for registration.") CellCh3
#@ Integer(label="Minimum intensity threshold:", value = 125, style="spinner") MaximaInt3
#@ Integer(label="Minimum cell area (um):", value = 20, style="spinner") Size3
//#@ Integer(label="Unsharp Mask radius (px, 0 if none):", value = 2, style="spinner") USRad
//#@ Double(label="Unsharp Mask weight:", value = 0.700, style="spinner") USMW
//#@ boolean(label="Measure intensity of each cell:", description="Leave off to save time. Enable to measured mean intensity of each channel for all detected cells.") MeasureInt
//#@ boolean(label="Display cell intensity on cell validation images:", description="Leave off to save time. Enable to see measured mean intensity overlayed on validation image.") IntVal

#@String  (visibility="MESSAGE", value="   ") out3
#@String  (visibility="MESSAGE", value="--------------------------------------------------------------Mesoscale Mapping/Projection Analysis Settings--------------------------------------------------------------") out4

#@ String(label="Method for mesoscale mapping axon/dendrite detection:", choices={"No Projection Analysis", "Binary Threshold", "Machine Learning Segmentation with Ilastik"}, value = "Machine Learning Segmentation with Ilastik", style="listBox", description="") ProjDetType
#@ String(label="Channel for mesoscale mapping analysis (0 for none):", choices={"1", "2", "3", "4", "0"}, style="radioButtonHorizontal", value = "1", description="Select the channel number containing DAPI or Autofluorescence, to be used for registration.") ProCh1
#@ Integer(label="Minimum intensity threshold:", value = 70, style="spinner") ProjectionInt1
#@ String(label="Additional channel for mesoscale mapping analysis:", choices={"1", "2", "3", "4", "0"}, style="radioButtonHorizontal", value = "0", description="Select the channel number containing DAPI or Autofluorescence, to be used for registration.") ProCh2
#@ Integer(label="Minimum intensity threshold:", value = 70, style="spinner") ProjectionInt2
#@ String(label="Additional channel for mesoscale mapping analysis:", choices={"1", "2", "3", "4", "0"}, style="radioButtonHorizontal", value = "0", description="Select the channel number containing DAPI or Autofluorescence, to be used for registration.") ProCh3
#@ Integer(label="Minimum intensity threshold:", value = 70, style="spinner") ProjectionInt3
//#@ Integer(label="Rolling ball prior to threshold. Radius (px, 0 if none):", value = 7, style="spinner", description="Performed on full resolution data, prior to any downscaling") BGSubPro


// SETTINGS FOR CHANGING RESOLUTION OF PROJECTION ANALYSIS - CURRENTLY ONLY 25um POSSIBLE BUT COULD DO THIS AT HIGHER RES WITH SOME MODIFICATION - LEAVE OFF OUT FOR V7
#@ Double(label="XY resolution used for projection density analysis (um/px):", value = 10.00, description="Higher resolution requires more RAM", style="spinner") ProDetectionResolution
//#@ Double(label="Section thickness/resolution used for projection density analysis (default 25) (um):", value = 25.00, description="Leave at 25um unless you are using sections thinner than 25um", style="spinner") ProDetectionResolutionZ

#@String  (visibility="MESSAGE", value="   ") out
#@String  (visibility="MESSAGE", value="--------------------------------------------------------------------------------------------------------------------------------------------------------------") out5
#@ File(label="Ilastik location (if using Ilastik for segmentation):", value = "C:/Program Files/ilastik-1.3.3post1", style="directory") IlastikDir
#@ File(label="Elastix location:", value = "C:/Program Files/elastix_v5_0", style="directory") ElastixDir
//#@ File(label="Atlas files location:", style="directory") AtlasDir
//#@ String(label="Atlas to align to:", choices={"25um template brain"}, style="listBox") AtlasType

//#@ boolean(label="Mask brain region to assist alignment?", description="Creates a binary mask of brain or tissue region to be aligned.") ExpBrainMaskON
//#@ boolean(label="Use a specific template file?", description="Uses a provided binary mask in the atlas space to assist alignment.") SpecificTemplateON
//#@ File(label="Brain template file:", value = "C:/select folder", style="file", description="Only required if performing specialized registration using a modified template.") AtlasTemplateLocation
//#@ boolean(label="Use a masked region in atlas?", description="Uses a provided binary mask in the atlas space to assist alignment.") AtlasMaskON
//#@ File(label="Atlas mask file:", value = "C:/select folder", style="file", description="Only required if performing an alignment assited by a mask.") AtlasMaskLocation


title1 = "Brain_Parameters"; 
title2 = "["+title1+"]"; 
f=title2; 
run("New... ", "name="+title2+" type=Table"); 
print(f,"\\Headings:Parameter\tValue");
	
print(f,"Directory:\t"+input); //0

print(f,"Reference section:\t"+RefSection); //1
print(f,"Peform Second Pass Reg?\t"+SecondPass); //25
print(f,"Full resolution DAPI\t"+FullResDAPI); //13


print(f,"Cell Resolution:\t"+CellDetectionResolution); //5


print(f,"Cell Detection Type:\t"+CellDetType); //26

print(f,"Cell Analysis 1:\t"+CellCh1); //2
print(f,"Cell Analysis Cell SizeC1:\t"+Size1); //9
print(f,"Maxima Int 1:\t"+MaximaInt1); //27
print(f,"Cell Analysis 2:\t"+CellCh2); //3
print(f,"Cell Analysis Cell SizeC2:\t"+Size2); //35
print(f,"Maxima Int 2:\t"+MaximaInt2); //28
print(f,"Cell Analysis 3:\t"+CellCh3); //4
print(f,"Cell Analysis Cell SizeC3:\t"+Size3); //36
print(f,"Maxima Int 3:\t"+MaximaInt3); //29


print(f,"Cell Analysis BG Subtraction:\t"+BGSub); //6
print(f,"Cell Analysis US Mask:\t"+USRad); //7
print(f,"Cell Analysis US Mask Weight:\t"+USMW); //8
print(f,"Intensity Validation:\t"+IntVal); //24

print(f,"Projection Detection Type:\t"+ProjDetType); //30
print(f,"Projection Analysis 1:\t"+ProCh1); //10
print(f,"Projection Analysis 2:\t"+ProCh2); //11
print(f,"Projection Analysis 3:\t"+ProCh3); //12

print(f,"Projection Min Intensity 1:\t"+ProjectionInt1); //31
print(f,"Projection Min Intensity 2:\t"+ProjectionInt2); //32
print(f,"Projection Min Intensity 3:\t"+ProjectionInt3); //33

print(f,"Projection ResolutionXY:\t"+ProDetectionResolution); //17
//print(f,"Projection Analysis BG Subtraction:\t"+BGSubPro); //18
print(f,"Projection Resolution Zsection:\t"+ProDetectionResolutionZ); //19


print(f,"Ilastik:\t"+IlastikDir); //20
print(f,"Elastix:\t"+ElastixDir); //21
//print(f,"Atlas Dir:\t"+AtlasDir); //22

print(f,"Atlas Type:\t"+AtlasType); //23

print(f,"Trim:\t"+TransVolumeTrim); //34


//print(f,"Mask experimental brain:\t"+ExpBrainMaskON); //35
//print(f,"Specific Template Brain:\t"+SpecificTemplateON); //36
//print(f,"Atlas Mask on:\t"+AtlasMaskON); //37
//print(f,"Atlas template location :\t"+AtlasTemplateLocation); //38
//print(f,"Atlas mask location:\t"+AtlasMaskLocation); //39
//print(f,"Atlas Type:\t"+AtlasType); //


print(f,"BrainJ Version:\t97"); //36
	
	
selectWindow(title1);	
saveAs("txt", input + "/Analysis_Settings.csv");
closewindow(title1);


function closewindow(windowname) {
	if (isOpen(windowname)) { 
      		 selectWindow(windowname); 
       		run("Close"); 
  		} 
}