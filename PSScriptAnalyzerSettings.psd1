@{
    # Rules to exclude from analysis.
    # These are suppressed because the scripts are interactive console wizards,
    # not reusable modules — the flagged patterns are by-design choices.
    ExcludeRules = @(
        # Write-Host is correct for colored console output in an interactive wizard.
        # Write-Output/Write-Information would pollute the pipeline or require
        # -InformationAction preferences the user won't set.
        'PSAvoidUsingWriteHost',

        # All 15 instances are calls to our own Show-StageHeader helper.
        # Positional args are fine for internal functions with a stable signature.
        'PSAvoidUsingPositionalParameters',

        # Update-EnvironmentPath reads PATH from registry and sets $env:Path.
        # It doesn't modify system state — ShouldProcess adds complexity with no value.
        'PSUseShouldProcessForStateChangingFunctions',

        # Test-CommandExists — the plural reads naturally ("does this command exist?").
        # Renaming to Test-CommandExist would be grammatically awkward.
        'PSUseSingularNouns',

        # File contains em-dashes in comments/strings (from user-facing text).
        # BOM is not required for PowerShell 5.1+ to handle UTF-8 correctly.
        'PSUseBOMForUnicodeEncodedFile'
    )
}
