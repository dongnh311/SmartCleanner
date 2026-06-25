rule EICAR_Test_File
{
    meta:
        description = "EICAR standard antivirus test file (harmless)"
    strings:
        $eicar = "EICAR-STANDARD-ANTIVIRUS-TEST-FILE"
    condition:
        $eicar
}
