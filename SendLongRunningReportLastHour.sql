--EXEC dbo.SendLongRunningReportLastHour;
CREATE PROCEDURE dbo.SendLongRunningReportLastHour
AS
BEGIN
    -- Threshold for duration of a job in minutes
    DECLARE @ThresholdDuration INT = 30;

    -- Create a table variable to store long running jobs
    DECLARE @LongRunningMessages TABLE
    (
        
        JobName NVARCHAR(128),
        StartTime NVARCHAR(128),
        RunStatus NVARCHAR(MAX),
	Duration NVARCHAR(MAX),
	RunDate DATE
    );

    -- Fetch long running jobs from all job IDs within the last hour
    INSERT INTO @LongRunningMessages (JobName, StartTime, RunStatus, Duration, RunDate)
    
SELECT 
	j.name,
	FORMAT(a.start_execution_date, 'HH:mm:ss tt') AS StartTime,
	CASE
		WHEN a.start_execution_date IS NULL THEN 'Not running'
		WHEN a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL THEN 'Running'
		WHEN a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NOT NULL THEN 'Not running'
	END AS 'RunStatus',
	FORMAT(DATEADD(SECOND, DATEDIFF(SECOND, a.start_execution_date, GETDATE()), '19000101'), 'HH:mm:ss') AS Duration,
	FORMAT(a.start_execution_date, 'yyyy-MM-dd') AS RunDate
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobactivity a
ON j.job_id = a.job_id
WHERE 
	session_id = (SELECT MAX(session_id) FROM msdb.dbo.sysjobactivity)
	AND (a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL)


    -- If there are long running jobs, send a single email notification with a formatted HTML table
    IF EXISTS (SELECT 1 FROM @LongRunningMessages)
    BEGIN
	DECLARE @subject VARCHAR(max);
	SET @subject = 'Long running jobs - ' + CONVERT(VARCHAR(12),GETDATE(),107);

        DECLARE @message NVARCHAR(MAX);	
        SET @message = '<html><body>' +
            '<p>Long running jobs for the last hour: </p>' +
            '<table style="border-collapse: collapse; padding : 0px">' +
        '<tr>
		<th style="border: 2px solid #8c0416;text-align:center;padding: 5px;background-color: #D70040;color: #FFFFFF;">Job Name</th>
		<th style="border: 2px solid #8c0416;text-align:center;padding: 5px;background-color: #D70040;color: #FFFFFF;">Status</th>
		<th style="border: 2px solid #8c0416;text-align:center;padding: 5px;background-color: #D70040;color: #FFFFFF;">Duration</th>
		<th style="border: 2px solid #8c0416;text-align:center;padding: 5px;background-color: #D70040;color: #FFFFFF;">Start Time</th>
		<th style="border: 2px solid #8c0416;text-align:center;padding: 5px;background-color: #D70040;color: #FFFFFF;">Date</th>
	</tr>';

        -- Construct the message with long running jobs, timestamps, job names, and duration in an HTML table
        SELECT @message = @message + 
        '<tr>
		<td style="border: 2px solid #8c0416;text-align:center;padding: 5px;">' + JobName + '</td>' +
		'<td style="border: 2px solid #8c0416;text-align:center;padding: 5px;">' + RunStatus + '</td>' +
		'<td style="border: 2px solid #8c0416;text-align:center;padding: 5px;">' + Duration + '</td>' +
		'<td style="border: 2px solid #8c0416;text-align:center;padding: 5px;">' + StartTime + '</td>' +
		'<td style="border: 2px solid #8c0416;text-align:center;padding: 5px;">' + CONVERT(NVARCHAR, RunDate, 120) + '</td>
	</tr>'
        FROM @LongRunningMessages;

        SET @message = @message + '</table></body></html>';

        -- Send a single email notification with the formatted HTML table
         EXEC msdb.dbo.sp_send_dbmail
		@profile_name = 'SQL Alerts',
		@recipients = 'test@gmail.com',
		@subject = @subject,
		@body = @message,
            	@body_format = 'HTML';
    END;
END;
