// Setup Brain Parameters Tool

// First open input directory and check for parameter file

// if parameter file exists - populate all the variables - if not then just proceed - doesn't seem to work but parameters persist so it should be easy to use


  
#@ File(label="Select folder:", description="Subfolder containing brain raw data", style="directory") input

#@ String(label="Analysis type:", choices={"Whole Brain", "Isolated Region"}, value = "Whole Brain", style="listBox") AnalysisType
#@ String(label="Sample type:", choices={"Mouse Brain: Coronal Sections", "Mouse Brain: Sagittal Sections", "Mouse Spinal Cord", "Smaller Sample"}, value = "Mouse Brain: Coronal Sections", style="listBox") SampleType
#@ String(label="Input image type:", choices={"2D Slices", "Z-Stack"}, value = "2D Slices", style="listBox") ImageType
#@ String(label="Do the sections require rotation?", choices={"No rotation", "Rotate 90 degrees right", "Rotate 90 degrees left"}, style="radioButtonHorizontal", description="Rotate sections as necessary so the dorsal surface of the brain is at the top of the image.") Rotation
#@ String(label="Do the sections require flipping?", choices={"No flipping", "Flip Vertically", "Flip Horizontally"}, style="radioButtonHorizontal", description="Flip sections as necessary so the dorsal surface of the brain is at the top of the image.") Flip

#@ String(label="File Order (alphanumeric or using slide coordinates):", choices={"Alphanumeric", "Nikon ND2 stage coodinates"}, value = "Nikon ND2 stage coodinates", style="listBox", description="") FileOrder
#@ String(label="Order of sections on slide:", choices={"Right and Down", "Left and Down", "Right", "Left", "Right and Up", "Left and Up" }, style="listBox", description="Right and Down = Top: 1, 2, 3 Bottom: 4, 5, 6 || Left and Down = Top: 3, 2, 1 Bottom: 6, 5, 4 || Right = 1, 2, 3") SliceArrangement


#@ BigDecimal(label="Lateral (XY) resolution of input (um):", value = 1, style="spinner") InputRes
#@ BigDecimal(label="Final resolution of image output (um/px):", value = 2.00, description="Leave as 0 for original resolution", style="spinner") FinalResolution
#@ Integer(label="Section cut thickness (um):", value = 50, style="spinner") ZCut

#@ String(label="Counterstain channel (e.g. DAPI or NeuroTrace):", choices={"1", "2", "3", "4", "5"}, style="radioButtonHorizontal", value = "2", description="Select the channel number containing DAPI or Autofluorescence, to be used for registration.") AlignCh
#@ Integer(label="Background intensity of counterstain channel:", value = 200, style="spinner", description="This value will be subtracted to allow better alignment") BGround
#@ boolean(label="Perform automatic tissue detection:", description="Automatic detection and segmentation of tissue sections.") AutoSeg
#@ String(label="Spinal cord range (start segment, end segment):", style="text field", value = "C1,L5", description="Providing a start and end segment for your SC dataset will ensure better registration.") SCSegRange

//#@String(visibility="MESSAGE", value="------------------------------------------------------------------Isolated Region/s Settings------------------------------------------------------------------") out2
//#@String(label="ABA region/s to be isolated (e.g. 96,101):", value = "", description="Provide comma separated ABA numbers to define region/s to be aligned and analyzed") RegionNumbers
//#@ File(label="Atlas files location:", style="directory") AtlasDir

title1 = "Brain_Parameters"; 
title2 = "["+title1+"]"; 
f=title2; 
run("New... ", "name="+title2+" type=Table"); 
print(f,"\\Headings:Parameter\tValue");

	
print(f,"Directory:\t"+input); //0
print(f,"Sample Type:\t"+SampleType); //1

print(f,"Rotation:\t"+Rotation); //3
print(f,"Flip:\t"+Flip); //4
print(f,"Slice Arrangement:\t"+SliceArrangement); //5
print(f,"Final Resolution:\t"+FinalResolution); //6
print(f,"Section cut thickness:\t"+ZCut); //7

print(f,"DAPI/Autofluorescence channel:\t"+AlignCh); //8

print(f,"Background intensity:\t"+BGround); //9
print(f,"File Ordering:\t"+FileOrder); //10
print(f,"Input Image Type:\t"+ImageType); //11

print(f,"Analysis Type:\t"+AnalysisType); //12	
//print(f,"ABA Region Numbers:\t"+RegionNumbers); 	
//print(f,"AtlasDir:\t"+AtlasDir); 

print(f,"Input Resolution:\t"+InputRes); //13
print(f,"Automatic Segmentation:\t"+AutoSeg); //14
print(f,"SC Segment Range:\t"+SCSegRange); //15

	
selectWindow(title1);	
saveAs("txt", input + "/Experiment_Parameters.csv");
closewindow(title1);


function closewindow(windowname) {
	if (isOpen(windowname)) { 
      		 selectWindow(windowname); 
       		run("Close"); 
  		} 
}