#!/usr/bin/perl
# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# $Source: src/build/buildpnor/buildpnor.pl $
#
# IBM CONFIDENTIAL
#
# COPYRIGHT International Business Machines Corp. 2012,2013
#
# p1
#
# Object Code Only (OCO) source materials
# Licensed Internal Code Source Materials
# IBM HostBoot Licensed Internal Code
#
# The source code for this program is not published or otherwise
# divested of its trade secrets, irrespective of what has been
# deposited with the U.S. Copyright Office.
#
# Origin: 30
#
# IBM_PROLOG_END_TAG
#Builds a PNOR image based on pnorLayout XML file.
#See usage function at bottom of file for details on how to use this script

#Limitations to address later
# number fields must be 4 or 8 bytes
# numbers cannot be over 32 bits


use strict;
use XML::Simple;
use Data::Dumper;
use File::Basename;
use Digest::SHA1;

################################################################################
# Set PREFERRED_PARSER to XML::Parser. Otherwise it uses XML::SAX which contains
# bugs that result in XML parse errors that can be fixed by adjusting white-
# space (i.e. parse errors that do not make sense).
################################################################################
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

my $TRAC_ERR = 0;
# 0=errors, >0 for more traces, leaving at 1 to keep key milestone traces.
my $g_trace = 1;

my $programName = File::Basename::basename $0;
my %pnorLayout;
my %binFiles;


my $pnorLayoutFile;
my $pnorBinName = "";
my $tocVersion = 0x1;
my $g_TOCEyeCatch = "part";
my $emitTestSections = 0;
my $g_ffsCmd = "";

if ($#ARGV < 0) {
    usage();
    exit;
}

#Parse the commandline args
for (my $i=0; $i < $#ARGV + 1; $i++)
{
    if ($ARGV[$i] =~ /-h/) {
        usage();
        exit 0;
    }
    elsif($ARGV[$i] =~ /--tocVersion/) {
        $tocVersion = getNumber($ARGV[++$i]);
        trace(2, "TOC Version to use=".sprintf("0x%x", $tocVersion));
    }
    elsif($ARGV[$i] =~ /--pnorLayout/) {
        $pnorLayoutFile = $ARGV[++$i];
        trace(2, "PNOR Layout XML File=$pnorLayoutFile");
    }
    elsif($ARGV[$i] =~ /--pnorOutBin/) {
        $pnorBinName = $ARGV[++$i];
        trace(2, "PNOR Binary File=$pnorBinName");
    }
    elsif($ARGV[$i] =~ /--binFile/) {
        my $argName = $ARGV[$i];
        my $argVal = $ARGV[++$i];
        saveInputFile("--binFile", $argName, $argVal, \%binFiles);
    }
    elsif($ARGV[$i] =~ /--ffsCmd/) {
        $g_ffsCmd = $ARGV[++$i];
    }
    elsif($ARGV[$i] =~ /--test/) {
        $emitTestSections = 1;
    }
    else {
        traceErr("Unrecognized Input: $ARGV[$i]");
        exit 1;
	#Error!!
    }
}

#TODO: Remove with RTC: 63500
#check for new ffs exec.  Use to trigger using new parms.
my $use_newFFSParms = 0;
my $ffsPath = "";
my $ffs_fh;
#Need a get complete path to ffs exec if none given
if(index($g_ffsCmd, '/',0) < 0)
{
    $ffsPath = `which $g_ffsCmd`;
}
else
{
    $ffsPath = $g_ffsCmd;
}

unless (open $ffs_fh, $ffsPath)
{
    traceErr("Unable to locate/open ffs exec: $g_ffsCmd.  Exiting.");
    exit 1;
}

my $sha1 = Digest::SHA1->new;
$sha1->addfile($ffs_fh);
my $sha_val = $sha1->hexdigest;
close $ffs_fh;

if($sha_val ne "b3b2110d73df1ac3f326762808a347ed2dc96323")
{
    trace(1, "New ffs exec detected (SHA1=$sha_val)");
    $use_newFFSParms = 1;
}
#end TODO remove with RTC: 63500

#Load PNOR Layout XML file
my $rc = loadPnorLayout($pnorLayoutFile, \%pnorLayout);
if($rc != 0)
{
    trace(0, "Error detected from call to loadPnorLayout().  Exiting");
    exit 1;
}

#trace(1, Dumper(%pnorLayout->{1576960}));
#trace(1, Dumper(%binFiles));

#Verify all the section files exist
my $rc = verifyFilesExist(\%pnorLayout, \%binFiles);
if($rc != 0)
{
    trace(0, "Error detected from call to verifyFilesExist().  Exiting");
    exit 1;
}

#Perform any data integrity manipulation (ECC, shaw-hash, etc)
$rc = robustifyImgs(\%pnorLayout, \%binFiles);
if($rc != 0)
{
    trace(0, "Error detected from call to robustifyImgs().  Exiting");
    exit 1;
}

#collect Actual image sizes
$rc = collectActSizes(\%pnorLayout, \%binFiles);
if($rc != 0)
{
    trace(0, "Error detected from call to collectActSizes().  Exiting");
    exit 1;
}

#calculates the acutal size of the TOC data and stores it away
$rc = fillTocActSize($tocVersion, \%pnorLayout);
if($rc != 0)
{
    trace(0, "Error detected from call to fillTocActSize().  Exiting");
    exit 1;
}

$rc = checkSpaceConstraints(\%pnorLayout, \%binFiles);
if($rc != 0)
{
    trace(0, "Error detected from call to checkSpaceConstraints().  Exiting");
    exit 1;
}

#create the PNOR image
$rc = createPnorImage($tocVersion, $pnorBinName, \%pnorLayout);
if($rc != 0)
{
    trace(0, "Error detected from call to createPnorImage().  Exiting");
    exit 1;
}

$rc = fillPnorImage($pnorBinName, \%pnorLayout, \%binFiles);
if($rc != 0)
{
    trace(0, "Error detected from call to fillPnorImage().  Exiting");
    exit 1;
}

exit 0;

################################################################################
# loadPnorLayout
################################################################################
sub loadPnorLayout
{
    my ($i_pnorFile, $i_pnorLayoutRef) = @_;
    my $this_func = (caller(0))[3];

    unless(-e $i_pnorFile)
    {
        traceErr("$this_func: File not found: $i_pnorFile");
        return -1;
    }

    #parse the input XML file
    my $xs = new XML::Simple(keyattr=>[], forcearray => 1);
    my $xml = $xs->XMLin($i_pnorFile);

    #trace(1, "pnorLayoutXML \n ".Dumper($xml));

    #Save the meatadata - imageSize, blockSize, etc.
    foreach my $metadataEl (@{$xml->{metadata}})
    {
        my $imageSize = $metadataEl->{imageSize}[0];
        my $blockSize = $metadataEl->{blockSize}[0];
        my $partTableSize = $metadataEl->{partTableSize}[0];
        my $sideAOffset = $metadataEl->{sideAOffset}[0];

        trace(3, "$this_func: metadata: imageSize = $imageSize, blockSize=$blockSize, partTableSize=$partTableSize, sideAOffset=$sideAOffset");

        $imageSize = getNumber($imageSize);
        $blockSize = getNumber($blockSize);
        $partTableSize = getNumber($partTableSize);
        $sideAOffset = getNumber($sideAOffset);

        $$i_pnorLayoutRef{metadata}{imageSize} = $imageSize;
        $$i_pnorLayoutRef{metadata}{blockSize} = $blockSize;
        $$i_pnorLayoutRef{metadata}{partTableSize} = $partTableSize;
        $$i_pnorLayoutRef{metadata}{sideAOffset} = $sideAOffset;
    }

    #Iterate over the <section> elements.
    foreach my $sectionEl (@{$xml->{section}})
    {
        #trace(1, "current Element: \n ".Dumper($sectionEl));
        my $description = $sectionEl->{description}[0];
        my $eyeCatch = $sectionEl->{eyeCatch}[0];
        my $physicalOffset = $sectionEl->{physicalOffset}[0];
        my $physicalRegionSize = $sectionEl->{physicalRegionSize}[0];
        my $ecc = $sectionEl->{ecc}[0];
        my $source = $sectionEl->{source}[0];
        my $sideless = $sectionEl->{sideless}[0];

        if (($emitTestSections == 0) && ($sectionEl->{testonly}[0] eq "yes"))
        {
            next;
        }

        my $actualRegionSize = 0;
        if(exists($sectionEl->{actualRegionSize}[0]))
        {
            $actualRegionSize = $sectionEl->{actualRegionSize}[0];
            $actualRegionSize = getNumber($actualRegionSize);
        }

        trace(3, "$this_func: description = $description, eyeCatch=$eyeCatch, physicalOffset = $physicalOffset, physicalRegionSize=$physicalRegionSize, ecc=$ecc, source=$source, actualRegionSize=$actualRegionSize");

        $physicalOffset = getNumber($physicalOffset);
        $physicalRegionSize = getNumber($physicalRegionSize);

        # trace(4, "$this_func: physicalOffset=$physicalOffset, physicalRegionSize=$physicalRegionSize");

        $$i_pnorLayoutRef{sections}{$physicalOffset}{description} = $description;
        $$i_pnorLayoutRef{sections}{$physicalOffset}{eyeCatch} = $eyeCatch;
        $$i_pnorLayoutRef{sections}{$physicalOffset}{physicalOffset} = $physicalOffset;
        $$i_pnorLayoutRef{sections}{$physicalOffset}{physicalRegionSize} = $physicalRegionSize;
        $$i_pnorLayoutRef{sections}{$physicalOffset}{actualRegionSize} = $actualRegionSize;
        $$i_pnorLayoutRef{sections}{$physicalOffset}{ecc} = $ecc;
        $$i_pnorLayoutRef{sections}{$physicalOffset}{source} = $source;
        $$i_pnorLayoutRef{sections}{$physicalOffset}{sideless} = $sideless;

    }

    return 0;
}

################################################################################
# createPnorImage - Create PNOR image and partitions based on input data.
################################################################################
sub createPnorImage
{
    my ($i_tocVersion, $i_pnorBinName, $i_pnorLayoutRef) = @_;
    my $this_func = (caller(0))[3];
    my $rc = 0;
    my $key;
    trace(4, "$this_func: >>Enter");

    #get Block size
    my $blockSize = $$i_pnorLayoutRef{metadata}{blockSize};

    #Get size of image in blocks
    my $imageSize = $$i_pnorLayoutRef{metadata}{imageSize};
    my $blockCount = $imageSize/$blockSize;
    if ($blockCount != int($blockCount))
    {
        trace(0, "$this_func: Image size ($imageSize) is not an even multiple of erase blocks ($blockSize).  This is not supported.  Aborting!");
        $rc = 1;
        return $rc;
    }

    #Offset of Partition Table A in PNOR
    my $sideAOffset =  $$i_pnorLayoutRef{metadata}{sideAOffset};

     # TODO: clean up with RTC: 63500
    if($use_newFFSParms == 1)
    {
        #ffs --create --target tuleta.pnor --partition-offset 0 --size 8MiB --block 4KiB --force
        my $ffsOut = `$g_ffsCmd --create --target $i_pnorBinName --partition-offset $sideAOffset --size $imageSize --block $blockSize --force`;
    }
    else
    {
        #ffs --create tuleta.pnor --partition-offset 0 --size 8MiB --block 4KiB --force
        my $ffsOut = `$g_ffsCmd --create $i_pnorBinName --partition-offset $sideAOffset --size $imageSize --block $blockSize --force`;
    }
    $rc = $?;
    if($rc)
    {
        trace(0, "$this_func: Call to ffs creating image failed.  rc=$rc.  Aborting!");
        return $rc;
    }

    #key into hash data is the physical offset of section.  Need to sort the keys
    #so we put things in the correct order in toc.
    #Generally speaking, this loop is populating the FFS Header with records based on the
    #section data specified in the XML + actual sizes of the input binary files.
    my %sectionHash = %{$$i_pnorLayoutRef{sections}};

    for $key ( sort {$a<=> $b} keys %sectionHash)
    {
        my $eyeCatch = "UNDEF";
        my $physicalOffset = 0xFFFFFFFF;
        my $physicalRegionSize = 0xFFFFFFFF;
        my $actualRegionSize = 0xFFFFFFFF;

        # eyecatcher
        my $eyeCatch = $sectionHash{$key}{eyeCatch};

        #don't try to add the eyeCatcher, but need to update user data
        if( $eyeCatch ne $g_TOCEyeCatch )
        {

            # base/physical offset
            my $physicalOffset = $sectionHash{$key}{physicalOffset};
            #make sure offset is on a block boundary
            my $val = $physicalOffset/$blockSize;
            if ($val != int($val))
            {
                trace(0, "$this_func: Partition offset ($val) is does not fall on an erase block ($blockSize) boundary.  This is not supported.  Aborting!");
                $rc = -1;
                last;
            }

            #physical size
            my $physicalRegionSize = $sectionHash{$key}{physicalRegionSize};
            $val = $physicalRegionSize/$blockSize;
            if($val != int($val))
            {
                trace(0, "$this_func: Partition size ($val) is not an even multiple of erase blocks ($blockSize).  This is not supported.  Aborting!");
                exit 1;
            }

            # TODO: clean up with RTC: 63500
            if($use_newFFSParms == 1)
            {
                #Create partition
                #ffs --add --target tuleta.pnor --partition-offset 0 --offset 0x1000   --size 0x280000 --name HBI --flags 0x0
                my $ffsOut = `$g_ffsCmd --add --target $i_pnorBinName --partition-offset $sideAOffset --offset $physicalOffset --size $physicalRegionSize --name $eyeCatch --flags 0x0`;
                #Force Actual Size = Partition size  (implicit when trunc is called with no value)
                #ffs --target tuleta.pnor --partition-offset 0 --name HBI --trunc
                my $ffsRc = `$g_ffsCmd --target $i_pnorBinName --partition-offset $sideAOffset --name $eyeCatch  --trunc`;

            }
            else
            {
                #ffs --add tuleta.pnor --partition-offset 0 --offset 0x1000 --size 0x280000 --name HBI --type data --flags 0x0
                my $ffsOut = `$g_ffsCmd --add $i_pnorBinName --partition-offset $sideAOffset --offset $physicalOffset --size $physicalRegionSize --name $eyeCatch --type data --flags 0x0`;
            }
            $rc = $?;
            if($rc)
            {
                trace(0, "$this_func: Call to ffs adding partition $eyeCatch failed.  rc=$rc.  Aborting!");
                last;
            }
        }

        # fill in user words 
        #User Word 1 - Actual size actual size
        my $actualRegionSize = $sectionHash{$key}{actualRegionSize};
        #verify number consumes less than 32 bits
        if($actualRegionSize > 0xFFFFFFFF)
        {
            trace(0, "value=".$actualRegionSize.".  This is greater than 32 bits in hex and not currently supported!. \n Aborting program");
            $rc = -1;
            last;
        }

        # TODO: clean up with RTC: 63500
        if($use_newFFSParms == 1)
        {
            #ffs --target tuleta.pnor --partition-offset 0 --name HBI --user 0 --value 0x12345678
            my $ffsRc = `$g_ffsCmd --target $i_pnorBinName --partition-offset $sideAOffset --name $eyeCatch  --user 0 --value $actualRegionSize`;
        }
        else
        {
            #ffs --modify tuleta.pnor --partition-offset 0 --name HBI --user 0 --value 0x12345678
            my $ffsRc = `$g_ffsCmd --modify $i_pnorBinName --partition-offset $sideAOffset --name $eyeCatch  --user 0 --value $actualRegionSize`;
        }
        $rc = $?;
        if($rc)
        {
            trace(0, "$this_func: Call to ffs setting user 0 for partition $eyeCatch failed.  rc=$rc.  Aborting!");
            last;
        }

        #User Word 2-3: Miscellaneous information.
        #User Word 2, bit 18 indicates sideless.
        my $miscInfo = 0x00000000;
        if($sectionHash{$key}{sideless} =~ "yes")
        {
            $miscInfo = $miscInfo | 0x00004000;
        }

        # TODO: clean up with RTC: 63500
        if($use_newFFSParms == 1)
        {
            #ffs --target tuleta.pnor --partition-offset 0 --name HBI --user 1 --value 0x12345678
            my $ffsRc = `$g_ffsCmd --target $i_pnorBinName --partition-offset $sideAOffset --name $eyeCatch  --user 1 --value $miscInfo`;
        }
        else
        {
            #ffs --modify tuleta.pnor --partition-offset 0 --name HBI --user 1 --value 0x12345678
            my $ffsRc = `$g_ffsCmd --modify $i_pnorBinName --partition-offset $sideAOffset --name $eyeCatch  --user 1 --value $miscInfo`;
        }
        $rc = $?;
        if($rc)
        {
            trace(0, "$this_func: Call to ffs setting user 1 for partition $eyeCatch failed.  rc=$rc.  Aborting!");
            last;
        }
    }

    return $rc;
}

################################################################################
# fillTocActSize - Fill in the toc actual size record based on number of PNOR records
################################################################################
sub fillTocActSize
{
    #Note: tocVersion is passed in because the toc Layout version could influence the
    #rules regarding how the size is calculated.
    my($i_tocVersion, $i_pnorLayoutRef) = @_;
    my $this_func = (caller(0))[3];
    my $rc = 0;
    my $ffsHeaderSize = 9*4;
    my $ffsEntrySize = getFFSEntrySize($i_tocVersion, $i_pnorLayoutRef);

    my %sectionHash = %{$$i_pnorLayoutRef{sections}};
    my $recordCount = scalar keys %sectionHash;
    my $size = ($recordCount*$ffsEntrySize)+$ffsHeaderSize;

    my $tocLayoutKey = findLayoutKeyByEyeCatch($g_TOCEyeCatch, \%$i_pnorLayoutRef);
    if( $tocLayoutKey == -1)
    {
        trace(0, "$this_func: Unable to find EyeCatcher=$g_TOCEyeCatch in PNOR layout for TOC entry. ");
        $rc = 1;
        last;
    }

    if($$i_pnorLayoutRef{sections}{$tocLayoutKey}{ecc} =~ "yes")
    {
        $size=$size*(9/8);
    }

    trace(2, "$this_func: PNOR FFS contains $recordCount records, total Size=$size");
    $$i_pnorLayoutRef{sections}{$tocLayoutKey}{actualRegionSize}=$size;


    return $rc;
}

################################################################################
# robustifyImgs - Perform any ECC or ShawHash manipulations
################################################################################
sub robustifyImgs
{
    my ($i_pnorLayoutRef, $i_binFiles) = @_;
    my $this_func = (caller(0))[3];

    #@TODO: ECC Correction
    #@TODO: maybe a little SHA hashing?

    return 0;
}

################################################################################
# collectActSizes - walk through all the images and set their actual sizes in the layout
################################################################################
sub collectActSizes
{
    my ($i_pnorLayoutRef, $i_binFiles) = @_;
    my $this_func = (caller(0))[3];
    my $key;
    my $rc = 0;

    for $key ( keys %{$i_binFiles})
    {
        my $filesize = -s $$i_binFiles{$key};

        my $layoutKey = findLayoutKeyByEyeCatch($key, \%$i_pnorLayoutRef);
        if( $layoutKey == -1)
        {
            trace(0, "$this_func: entry not found in PNOR layout for file $$i_binFiles{$key}, under eyecatcher $key");
            $rc = 1;
            last;
        }

        $$i_pnorLayoutRef{sections}{$layoutKey}{actualRegionSize} = $filesize;

        trace(2, "$this_func: $$i_binFiles{$key} size = $$i_pnorLayoutRef{sections}{$layoutKey}{actualRegionSize}");

    }

    return $rc;
}

################################################################################
# findLayoutKeyByEyeCatch - Figure out hash key based on eyeCatcher
################################################################################
sub findLayoutKeyByEyeCatch
{
    my $layoutKey = -1;
    my($eyeCatch, $i_pnorLayoutRef) = @_;
    my $key;

    my %sectionHash = %{$$i_pnorLayoutRef{sections}};
    for $key ( keys %sectionHash)
    {
        if($sectionHash{$key}{eyeCatch} =~ $eyeCatch)
        {
            $layoutKey = $key;
            last;
        }
    }

    return $layoutKey;
}

################################################################################
# verifyFilesExist - Verify all the input files exist, and there are files
#        provided for each PNOR section
################################################################################
sub verifyFilesExist
{
    my ($i_pnorLayoutRef, $i_binFiles) = @_;
    my $this_func = (caller(0))[3];
    my $key;
    my $rc = 0;

    for $key ( keys %$i_binFiles)
    {
        unless(-e $$i_binFiles{$key})
        {
            my $inputFile = $$i_binFiles{$key};
            trace(0, "Specified input file ($inputFile) for key ($key) does not exist.  Aborting!");
            $rc = 1;
            last;
        }
        else
        {
            trace(10, "$this_func: $$i_binFiles{$key} exists");
        }
    }

    if($rc != 0)
    {
        return $rc;
    }

    my %sectionHash = %{$$i_pnorLayoutRef{sections}};

    #Verify there is an input file for each section of PNOR
    for $key ( keys %sectionHash)
    {
        my $eyeCatch = $sectionHash{$key}{eyeCatch};

        #Ignore sections that are marked as blank
        if($sectionHash{$key}{source} =~ "Blank")
        {
            next;
        }
        #check if binFiles list has a file for eyeCatcher
        unless(exists($$i_binFiles{$eyeCatch}))
        {
            my $inputFile = $$i_binFiles{$eyeCatch};
            trace(0, "Input file not provided for PNOR section with eyeCatcher=$eyeCatch.  Aborting!");
            $rc = 1;
            last;
        }
        else
        {
            trace(10, "$this_func: Input file ($$i_binFiles{$eyeCatch}) provided for section $eyeCatch");
        }
    }

    return $rc;
}

################################################################################
# checkSpaceConstraints - Make sure provided files will fit in their sections
################################################################################
sub checkSpaceConstraints
{
    my ($i_pnorLayoutRef, $i_binFiles) = @_;
    my $rc = 0;
    my $this_func = (caller(0))[3];
    my $key;

    my %sectionHash = %{$$i_pnorLayoutRef{sections}};
    #Verify there is an input file for each section of PNOR
    for $key ( keys %sectionHash)
    {
        my $eyeCatch = $sectionHash{$key}{eyeCatch};
        my $physicalRegionSize = $sectionHash{$key}{physicalRegionSize};
        my $actualRegionSize = $sectionHash{$key}{actualRegionSize};

        if($actualRegionSize > $physicalRegionSize)
        {
            trace(0, "$this_func: Image provided ($$i_binFiles{$eyeCatch}) has size ($actualRegionSize) which is greater than allocated space ($physicalRegionSize) for section=$eyeCatch.  Aborting!");
            $rc = 1;
        }

    }

    return $rc;
}

################################################################################
# fillPnorImage - Load actual PNOR image with data using the provided input images
################################################################################
sub fillPnorImage
{
    my ($i_pnorBinName, $i_pnorLayoutRef, $i_binFiles) = @_;
    my $this_func = (caller(0))[3];
    my $rc = 0;
    my $key;

    my $sideAOffset =  $$i_pnorLayoutRef{metadata}{sideAOffset};

    #key is the physical offset into the file, however don't need to sort
    #since FFS allows populating partitions in any order
    my %sectionHash = %{$$i_pnorLayoutRef{sections}};
    for $key ( keys %sectionHash)
    {
        trace(3, "$this_func: key=$key");
        my $eyeCatch = $sectionHash{$key}{eyeCatch};
        my $physicalOffset = $sectionHash{$key}{physicalOffset};
        my $inputFile = $$i_binFiles{$eyeCatch};

        #Ignore sections that are marked as blank
        if($sectionHash{$key}{source} =~ "Blank")
        {
            next;
        }

        trace(5, "$this_func: populating section $eyeCatch, filename=$inputFile");
        # TODO: clean up with RTC: 63500
        if($use_newFFSParms == 1)
        {
            #ffs --target tuleta.pnor --partition-offset 0 --name HBI --write hostboot_extended.bin
            my $ffsRc = `$g_ffsCmd --target $i_pnorBinName --partition-offset $sideAOffset --name $eyeCatch  --write $inputFile`;
        }
        else
        {
            #ffs --write tuleta.pnor --partition-offset 0 --name HBI --pad 0xff --data hostboot_extended.bin
            my $ffsRc = `$g_ffsCmd --write $i_pnorBinName --partition-offset $sideAOffset --name $eyeCatch  --pad 0xff --data $inputFile`;
        }
        $rc = $?;
        if($rc)
        {
            trace(0, "$this_func: Call to ffs adding data to partition $eyeCatch failed.  rc=$rc.  Aborting!");
            last;
        }

    }

    return $rc;
}

################################################################################
# saveInputFile - save inputfile name into binFiles array
################################################################################
sub saveInputFile
{
    my ($i_argPrefix, $i_argName, $i_argVal, $i_binFiles) = @_;
    my $this_func = (caller(0))[3];

    #$i_argName will be something like --binFile_HBB
    #This substr command should return just the HBB, which should match an eyeCather
    my $eyeCatcher = substr($i_argName, length($i_argPrefix)+1, length($i_argName)-length($i_argPrefix));

    trace(10, "$this_func: $eyeCatcher=$i_argVal");

    $$i_binFiles{$eyeCatcher} = $i_argVal;

    trace(10, "$this_func:           $$i_binFiles{$eyeCatcher}");

    #no return code expected
}

#################################################
# getFFSEntrySize: Returns number of bytes in an ffs_entry based on specified version
#################################################
sub getFFSEntrySize
{
    my($i_tocVersion, $i_pnorLayoutRef) = @_;
    my $this_func = (caller(0))[3];
    my $ffsEntrySize = 0;

    if($i_tocVersion == 0x1)
    {
        #16 char name + 12 fixed words + 16 user data words
        $ffsEntrySize = 16+(12*4)+(16*4);
    }
    else
    {
        trace(0, "$this_func:  Layout Version Unsupported!  i_tocVersion=$i_tocVersion");
        exit 1;
    }
    return $ffsEntrySize;
}

#################################################
# Insert specifed number of pad bytes into file
#
#################################################
sub insertPadBytes
{
    my ($i_FILEHANDLE, $i_padBytes) = @_;
    my $i;
    print $i_FILEHANDLE pack("C[$i_padBytes]", map { 0 } 1..$i_padBytes);

}

################################################################################
# getNumber - handle hex or decimal input string
################################################################################
sub getNumber
{
    my $inVal = shift;
    if($inVal =~ "0x")
    {
	return oct($inVal);
    }
    else
    {
	return $inVal;
    }
}

################################################################################
# trace
################################################################################
sub traceErr
{
    my $i_string = shift;
    trace($TRAC_ERR, $i_string);
}

################################################################################
# trace
################################################################################
sub trace
{
    my $i_traceLevel;
    my $i_string;

    ($i_traceLevel, $i_string) = @_;

    #traceLevel 0 is for errors
    if($i_traceLevel == 0)
    {
	print "ERROR: ".$i_string."\n";
    }
    elsif ($g_trace >= $i_traceLevel)
    {
	print "TRACE: ".$i_string."\n";
    }
}



################################################################################
# print usage instructions
################################################################################
sub usage
{
print <<"ENDUSAGE";
  $programName = Creates the PNOR IMAGE and with TOC based on input data.

  Usage:
    $programName --pnorlayout <layout xml file> --genToc --tocVersion <TOC layout version
                 --pnorOutBin  <complete PNOR image>
                 --binFile_HBB <hostboot base image> --binFile_HBI <hostboot extended image>

  Parms:
    -h                  Print this help text
    --pnorlayout <file> PNOR Layout XML file
    --pnorOutBin <file> Name of output file for PNOR Binary
    --genToc            Indicates you wish to generate a table of contents.  It will
                        write the file indicated by --binFile_TOC.

    --binFile_<Section> <file>  This is a special paramater.  It is used to specify
                        input files to use for populating the various sections of
                        PNOR.
                            Examples:  --binFile_HBB hostboot.bin
                                       --binFile_HBI hostboot_extended.bin
                                       --binFile_TOC murano.toc
                         A section declared as Blank in the XML does not need to have a
                         binFile specified
    --ffsCmd             invoke string for executing the ffs tool
    --test              Output test-only sections.

  Current Limitations:
      --TOC Records must be 4 or 8 bytes in length
      --Regions and offsets cannot be over 32 bits (in hex), not an issue with current PNOR size
     The script will print and error and exit with a non-zero return code if these
     conditions are encountered.

ENDUSAGE
}
