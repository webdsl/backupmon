package org.webdsl.backupmon;

import java.io.File;
import java.io.FileFilter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class FileUtils {

	public static List<File> files(String pathToDir) {
		File dir = new File(pathToDir);
		List<File> toReturn = new ArrayList<File>();
		if (dir.exists()) {
			// Location file (directory) first
			toReturn.add(dir);
			File[] listOfFiles = dir.listFiles(noDirs);
			toReturn.addAll(Arrays.asList(listOfFiles));
		}
		return toReturn;
	}

	private static FileFilter noDirs = new FileFilter() {
		@Override
		public boolean accept(File path) {
			return path.isFile();
		}
	};
}
