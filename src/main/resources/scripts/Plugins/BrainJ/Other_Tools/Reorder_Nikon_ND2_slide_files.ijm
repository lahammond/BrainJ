// ND2 File Order Renaming
 
// Author: 	Luke Hammond (lh2881@columbia.edu)
// Zuckerman Institute, Columbia University
// Date:	30th September 2019
//	
//	Renaming of ND2 files based on their stage coordinates- part of BrainJ but for data that needs to be order for other pipelines
// 			
// 	Usage:
//		1. Select folders containing ND2 files
//
// Updates:


// Initialization

#@ File[] listOfPaths(label="select files or folders", style="both")

//#@ String(label="File Order (alphanumeric or using slide coordinates):", choices={"Alphanumeric", "Nikon ND2 stage coodinates"}, value = "Nikon ND2 stage coodinates", style="listBox", description="") FileOrder
#@ String(label="Order of sections on slide:", choices={"Right and Down", "Left and Down", "Right", "Left", "Right and Up", "Left and Up" }, style="listBox", description="Right and Down = Top: 1, 2, 3 Bottom: 4, 5, 6 || Left and Down = Top: 3, 2, 1 Bottom: 6, 5, 4 || Right = 1, 2, 3") SectionArrangement


print("\\Clear");
print("\\Update0:Renaming ND2 files");
setBatchMode(true);

// Start processing folders:
print("\\Update1: "+listOfPaths.length+" folders selected for processing.");

for (FolderNum=0; FolderNum<listOfPaths.length; FolderNum++) {
	
	inputdir=listOfPaths[FolderNum];
	
	if (File.exists(inputdir)) {
    	if (File.isDirectory(inputdir) == 0) {
        	print(inputdir + "Is a file, please select only directories containing brain datasets.");
        } else {
			print("\\Update3: Renaming files according to ND2 stage coordinates...");
			inputdir = inputdir + "/";
			RenameSectionFilesFromND2Coord(inputdir);
			print("\\Update3: Renaming files according to ND2 stage coordinates... Complete.");

        }
	}
}


function RenameSectionFilesFromND2Coord(input) {
	
	files = getFileList(input);	
	files = ImageFilesOnlyArray(files);		
	files = Array.sort( files );
	for(filen=0; filen<files.length; filen++) {				
		image = files[filen];	
		

		run("Bio-Formats Macro Extensions");
		Ext.setId(input + image);
		Ext.getMetadataValue("dXPos", XPos);
		Ext.getMetadataValue("dYPos", YPos);

		
		//run("Bio-Formats Importer", "open=[" + input + image + "] color_mode=Default display_metadata rois_import=[ROI manager] view=[Metadata only] stack_order=Default");
		//selectWindow("Original Metadata - " + image );
		//saveAs( "Results", input + "temp_metadata.txt" );
		//selectWindow("Original Metadata - " + image );
		//run("Close");

		// Process name
				
		names=split(image, "/");
		if (names.length > 1) {
			image = names[(names.length-1)];
		}
		smTitle = substring(image,0,9);
		//Elements 5.11 changed the file naming. So included this to fix:
		if(substring(image,6,7) == "-"){
			if(substring(image,8,9) == "_"){
				slide511=100+parseInt(substring(image,7,8));
			} else {
				slide511=100+parseInt(substring(image,7,9));
			}
			smTitle = "Slide"+slide511+"_";
		}

			
		//Get Metadata from Image
				
		//Metadata = split( File.openAsString( input + "temp_metadata.txt" ), "\n" );
	
		
		
		//for(i=0; i<Metadata.length; i++){ 
			//if(matches(Metadata[i],".*dXPos.*") == 1){
				//XRow=i;
			//}
			//if(matches(Metadata[i],".*dYPos.*") == 1){
				//YRow=i;
			//}
		//}
	
		//XPos=substring(Metadata[XRow],8,10);
		//YPos=substring(Metadata[YRow],8,10);
	
		if (SectionArrangement == "Right and Down"){
			if (YPos >=30) {
				YPos = 1;
			} else {
				YPos = 2;
			}
			XPos = round((1/XPos)*10000);
			XY_Title = smTitle + "_Y_"+ YPos +"_X_"+ XPos +".nd2";
			print("\\Update11:Sections are being ordered according to Right and Down arrangement.");
			print("\\Update12:E.g. Top: 1, 2, 3, 4 | Bottom: 5, 6, 7, 8");
		}
		if (SectionArrangement == "Left and Down"){
			if (YPos >=30) {
				YPos = 1;
			} else {
				YPos = 2;
			}
			XY_Title = smTitle + "_Y_"+ YPos +"_X_"+ XPos +".nd2";
			print("\\Update11:Sections are being ordered according to Left and Down arrangement.");
			print("\\Update12:E.g. Top: 4, 3, 2, 1 | Bottom: 8, 7, 6, 5");
		}
		if (SectionArrangement == "Right and Up"){
			if (YPos >=30) {
				YPos = 2;
			} else {
				YPos = 1;
			}
			XPos = round((1/XPos)*10000);
			XY_Title = smTitle + "_Y_"+ YPos +"_X_"+ XPos +".nd2";
			print("\\Update11:Sections are being ordered according to Right and Up arrangement.");
			print("\\Update12:E.g. Bottom: 1, 2, 3, 4 | Top: 5, 6, 7, 8");
		}
		if (SectionArrangement == "Left and Up"){
			if (YPos >=30) {
				YPos = 2;
			} else {
				YPos = 1;
			}
			XY_Title = smTitle + "_Y_"+ YPos +"_X_"+ XPos +".nd2";
			print("\\Update11:Sections are being ordered according to Left and Up arrangement.");
			print("\\Update12:E.g. Bottom: 4, 3, 2, 1 | Top: 8, 7, 6, 5");
		}
		if (SectionArrangement == "Right"){
			if (YPos >=30) {
				YPos = 1;
			} else {
				YPos = 2;
			}
			XPos = round((1/XPos)*10000);
			XY_Title = smTitle + "_X_"+ XPos +"_Y_"+ YPos +".nd2";
			print("\\Update11:Sections are being ordered according to Right arrangment.");
			print("\\Update12:E.g. Top: 1, 3, 5, 7 | Bottom: 2, 4, 6, 8");
			print("\\Update13:This arrangement can lead to some sections being out of step. When checking file names, order should be Y_1, then Y_2. If you see instances of Y_2 then Y_1, reduce the X_ value in the filename to correct.");
		}
		if (SectionArrangement == "Left"){
			if (YPos >=30) {
				YPos = 1;
			} else {
				YPos = 2;
			}
			XY_Title = smTitle + "_X_"+ XPos +"_Y_"+ YPos +".nd2";
			print("\\Update11:Sections are being ordered according to Left arrangement.");
			print("\\Update12:E.g. Top: 7 , 5, 3, 1 | Bottom: 8, 6, 4, 2");
			print("\\Update13:This arrangement can lead to some sections being out of step. When checking file names, order should be Y_1, then Y_2. If you see instances of Y_2 then Y_1, reduce the X_ value in the filename to correct.");
		} 
		if (SectionArrangement == "Right (single row)"){
			XPos = round((1/XPos)*10000);
			XY_Title = smTitle +"_X_"+ XPos +".nd2";
			print("\\Update11:Sections are being ordered according to Right and Down arrangement.");
			print("\\Update12:E.g. Top: 1, 2, 3, 4 | Bottom: 5, 6, 7, 8");
		}
		if (SectionArrangement == "Left (single row)"){
			XY_Title = smTitle +"_X_"+ XPos +".nd2";
			print("\\Update11:Sections are being ordered according to Left and Down arrangement.");
			print("\\Update12:E.g. Top: 4, 3, 2, 1 | Bottom: 8, 7, 6, 5");
		}
		
		ok = File.rename(input + image, input + XY_Title);
		ok = File.delete(input + "temp_metadata.txt");
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
