
#@ File(label="Select projection image:", description="", style="file") projfile
#@ File(label="Select output folder:", style="directory") OutputDir
#@ File(label="Select template/annotation direcotry to be used (e.g. ABA CCF 2017):", style="directory") AtlasDir

#@ String(label="Filter type:", choices={"Mean", "Median"}, value = "Median", style="listBox") FilterType
#@ Double(label="Filter radius:", value = 1, style="spinner") FilterRad

print("\\Clear");

print("Creating projections overlayed with template and 3D images for selected image:");
print(" "+projfile);
print(FilterType + " " + FilterRad);

filenames = split(projfile, "\\");
filename = filenames[filenames.length-1]


setBatchMode(true);
// import atlas
open(AtlasDir + "/Template.tif");



rename("Template");
setMinAndMax(0, 600);
run("8-bit");


//import projections
open(projfile);	
rename("Projections");

if (FilterType == "Mean"){
	run("Mean...", "radius="+FilterRad+" stack");
}

if (FilterType == "Median"){
	run("Median...", "radius="+FilterRad+" stack");
}


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

print("Saving project and template overlay");
saveAs("Tiff", OutputDir + "/Templated_Overlay_"+FilterType+FilterRad+"_"+filename);
print("Rendering 3D image");
run("3D Project...", "projection=[Brightest Point] axis=Y-Axis slice=25 initial=0 total=360 rotation=10 lower=1 upper=255 opacity=0 surface=100 interior=50");
saveAs("Tiff", OutputDir + "/Templated_Overlay_3D_"+FilterType+FilterRad+"_"+filename);

close("*");
print("  Complete.");


