/// A simple and potentially dangerous zip utility to test Zip64 support in std/zip.d
/// Do not use this on any critical data!
///
/// \author Ferdynand Górski <home@fgda.pl>
/// \copyright Ferdynand Górski 2015.
/// Distributed under the Boost Software License, Version 1.0. 
/// See a copy at http://www.boost.org/LICENSE_1_0.txt.


import std.stdio, std.file, std.path, std.getopt;
import std.algorithm : endsWith;
import std.datetime : DosFileTimeToSysTime;

// Until changes to zip.d are merged, use std_zip_mod.d instead
version(work) {
    import std_zip_mod; 
} else {
    import std.zip; 
}

void printUsage(string appName)
{
    writeln("\nA small zip/unzip utility to test the D std.zip.d module.");
    writeln("Without the -c option it treats FILES as zip archives and unpacks them here.\n");
    writefln("Usage: %s [OPTIONS...] [FILES...]\n", appName);
    writeln("Options:");
    writeln("  -c, --compress=OUTPUT.zip  Creates OUTPUT.zip from FILES.");
    writeln("  -t, --test                 Dry run, doesn't write any files to disk.");
    writeln("  -z, --zip64                Forces the use of Zip64 format (used with -c).");
    writeln("  -h, --help                 This help screen.\n");
}

int main(string[] args)
{
    bool compress, test, forceZip64, showHelp;
    string zipFile;
    string inputFile;
    ulong maxFileSize = 100 * 1024 * 1024;
    ulong maxScan = 10 * 1024 * 1024;
    try {
        args.getopt(
            "compress|c", &zipFile,
            "test|t", &test,
            "zip64|z", &forceZip64,
            "help|h", &showHelp,
        );
    } catch (Exception e) {
        writeln("Error: ", e.msg);
        printUsage(args[0]);
        return 1;
    }
    if (showHelp || args.length == 1) {
        printUsage(args[0]);
        return 0;
    }
    
    if (zipFile.length) {
        compress = true;
        if (extension(zipFile) != ".zip") {
            writefln("Error: expected a file with .zip eztension and not this: %s", zipFile);
            return 1;
        }
        auto zip = new ZipArchive();
        if (forceZip64) {
            writefln("Forcing creation of Zip64 format archive.");
            zip.isZip64 = true;
        }
        uint count = 0;
        uint scanNum = 0;
        
        void addFile(string file)
        {
            // writeln(file);
            scanNum++;
            if (scanNum >= maxScan)
                return;
            
            if (!exists(file) || !isFile(file))
                return;
            
            if (getSize(file) > maxFileSize) {
                writefln("Warning: skipping file %s - it is too big, max size is %d", file, maxFileSize);
                return;
            }
            // writefln("Adding: %8d:%12d B   %s", count, getSize(file), file);
            writefln("Adding:%6d:%8d B - attr %s - %s - %s", count, getSize(file), 
                getAttributes(file), timeLastModified(file), file);
            count++;
            
            void[] data = std.file.read(file);
            auto am = new ArchiveMember();
            am.name = file;
            am.compressionMethod(CompressionMethod.deflate);
            am.expandedData = cast(ubyte[]) data;
            am.fileAttributes(getAttributes(file));
            am.time(timeLastModified(file));
            zip.addMember(am);
        }
        
        foreach (file; args[1..$]) {
            file = buildNormalizedPath(file);
            if (!exists(file)) {
                writefln("Warning: file doesn't exist: %s", file);
                continue;
            }
            if (isFile(file))
                addFile(file);
            else if (isDir(file))
                foreach (string name; dirEntries(file, SpanMode.depth))
                    addFile(name);
        }
        writefln("Building zip file...");
        auto zipData = zip.build();
        if (test) {
            writefln("This was a test run - no files will be written.");
            return 0;
        }
        writefln("Writing zip file: %s", zipFile);
        try { std.file.write(zipFile, zipData); }
        catch (Exception e) {
            writefln("Error writing zip file: %s", e.msg);
            return 2;
        }
        return 0;
    }
    
    foreach (file; args[1..$]) {
        if (extension(file) != ".zip") {
            writefln("Error: expected a file with .zip eztension and not this: %s", file);
            return 1;
        }
        if (!exists(file) || !isFile(file)) {
            writefln("Error: no such file: %s", file);
            return 1;
        }
        if (getSize(file) > maxFileSize) {
            writefln("Error: file %s is too big, max size is %d", file, maxFileSize);
            return 1;
        }
        writefln("Opening archive: %s", file);
        void[] data = std.file.read(file);
        auto zip = new ZipArchive(data);
        if (zip.isZip64)
            writefln("It's a Zip64 archive");
        uint count = 0;
        foreach (am; zip.directory) {
            if (am.name.endsWith("/", "\\")) {
                // writefln("Skipping directory: %s", am.name);
                continue;
            }
            string path = buildNormalizedPath(am.name);
            string directory = dirName(path);
            auto mtime = DosFileTimeToSysTime(am.time);
            writefln("File:%6d:%8d/%8d B - attr %s - v.%04x - %s - %s", count + 1, 
                am.compressedSize, am.expandedSize, am.fileAttributes, 
                am.extractVersion, mtime, am.name);
                
            count++;
            
            if (test)
                continue;
            
            if (!exists(directory)) {
                try {
                    // writefln("Creating directory: %s", directory);
                    mkdirRecurse(directory);
                }
                catch (Exception e) {
                    writefln("Error creating directory: %s - %s", directory, e.msg);
                    return 2;
                }
            }
            if (exists(path) && isDir(path))
                continue;
            
            try { 
                std.file.write(path, zip.expand(am));
                setAttributes(path, am.fileAttributes);
                setTimes(path, mtime, mtime);
            }
            catch (Exception e) {
                writefln("Error writing file: %s - %s", path, e.msg);
                return 2;
            }
        }
        if (test)
            writefln("This was a test run - no files were written.");
        
    }
    return 0;
}

