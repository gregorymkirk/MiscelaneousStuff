### I didn't write this, but as a sublime text user I find this really useful on windows.
### Orginal and discussion can be found at: https://gist.github.com/roundand/9367852#file-openwithsublimetext3-bat


@echo off


SET st3Path=C:\Program Files\Sublime Text 3\sublime_text.exe

# I commented this out as I already had this set up with the sublime text installer. 
# add it for all file types
#@reg add "HKEY_CLASSES_ROOT\*\shell\Open with Sublime Text 3"         /t REG_SZ /v "" /d "Open with Sublime Text 3"   /f
#@reg add "HKEY_CLASSES_ROOT\*\shell\Open with Sublime Text 3"         /t REG_EXPAND_SZ /v "Icon" /d "%st3Path%,0" /f
#@reg add "HKEY_CLASSES_ROOT\*\shell\Open with Sublime Text 3\command" /t REG_SZ /v "" /d "%st3Path% \"%%1\"" /f
 
# add it for folders
@reg add "HKEY_CLASSES_ROOT\Folder\shell\Open with Sublime Text 3"         /t REG_SZ /v "" /d "Open with Sublime Text 3"   /f
@reg add "HKEY_CLASSES_ROOT\Folder\shell\Open with Sublime Text 3"         /t REG_EXPAND_SZ /v "Icon" /d "%st3Path%,0" /f
# There is some discussion on the gist about whehter to use %1 or %%1.  I ended up using %1. 
# I ran it at the command line, not as a batch file. % and %% beuave differnetly in batch vs command line so 
# that's probalby the explanation.
@reg add "HKEY_CLASSES_ROOT\Folder\shell\Open with Sublime Text 3\command" /t REG_SZ /v "" /d "%st3Path% \"%%1\"" /f
pause