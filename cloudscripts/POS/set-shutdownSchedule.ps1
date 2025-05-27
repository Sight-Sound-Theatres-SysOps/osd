<#
This script creates a new scheduled task action to execute the shutdown.exe 
The trigger for the task is set to run at midnight on every day of the week except for Wednesday. 
The task is then registered with the name "AutoShutdown"
#>

$Trigger= New-ScheduledTaskTrigger -At 12:00am -DaysOfWeek Monday,Tuesday,Thursday,Friday,Saturday -Weekly # every day except Wednesday (updates) and Sunday (not on)
$User= "NT AUTHORITY\SYSTEM" # Specify the account to run the script
$Action= New-ScheduledTaskAction -Execute "C:\Windows\System32\shutdown.exe" -Argument "-s -t 100 -f" # Specify what program to run and with its parameters
Register-ScheduledTask -TaskName "AutoShutdown" -Trigger $Trigger -User $User -Action $Action -RunLevel Highest # Specify the name of the task
