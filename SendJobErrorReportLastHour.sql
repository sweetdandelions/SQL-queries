--EXEC dbo.SendJobErrorReportLastHour;
CREATE PROCEDURE dbo.SendJobErrorReportLastHour
AS
BEGIN
    -- Calculate the timestamp for one hour ago
    DECLARE @OneHourAgo DATETIME = DATEADD(HOUR, -1, GETDATE());

    -- Create a table variable to store error messages
    DECLARE @ErrorMessages TABLE
    (
        
        JobName NVARCHAR(128),
        StepName NVARCHAR(128),
        ErrorMessage NVARCHAR(MAX),
		    ErrorTime DATETIME
    );

    -- Fetch error messages from all job IDs within the last hour
    INSERT INTO @ErrorMessages (JobName, StepName, ErrorMessage, ErrorTime)
    SELECT
        jobs.name AS JobName,
        step.step_name AS StepName,
        hist.message AS ErrorMessage,
		    CONVERT(DATETIME, CONVERT(VARCHAR(8), hist.run_date, 112) + ' ' +
            STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), hist.run_time), 6), 3, 0, ':'), 6, 0, ':')) AS ErrorTime
    FROM msdb.dbo.sysjobhistory hist
    INNER JOIN msdb.dbo.sysjobs jobs ON hist.job_id = jobs.job_id
    INNER JOIN msdb.dbo.sysjobsteps step ON hist.job_id = step.job_id AND hist.step_id = step.step_id
    WHERE hist.run_status = 0
    AND CONVERT(DATETIME, CONVERT(VARCHAR(8), hist.run_date, 112) + ' ' +
            STUFF(STUFF(RIGHT('000000' + CONVERT(VARCHAR(6), hist.run_time), 6), 3, 0, ':'), 6, 0, ':')) >= @OneHourAgo;

    -- If there are error messages, send a single email notification with a formatted HTML table
    IF EXISTS (SELECT 1 FROM @ErrorMessages)
    BEGIN
		DECLARE @subject VARCHAR(max);
		SET @subject = 'Job Step Error Report - '+CONVERT(VARCHAR(12),GETDATE(),107);

        DECLARE @message NVARCHAR(MAX);
		
        SET @message = '<html><body>' +
            '<p>Error Messages for the Last Hour: + </p>' +
            '<table style="border-collapse: collapse; padding : 0px">' +
            '<tr>
			          <th style="border: 2px solid #8c0416;text-align:center;padding: 5px;background-color: #D70040;color: #FFFFFF;">Job Name</th>
			          <th style="border: 2px solid #8c0416;text-align:center;padding: 5px;background-color: #D70040;color: #FFFFFF;">Step Name</th>
			          <th style="border: 2px solid #8c0416;text-align:center;padding: 5px;background-color: #D70040;color: #FFFFFF;">Error Message</th>
			          <th style="border: 2px solid #8c0416;text-align:center;padding: 5px;background-color: #D70040;color: #FFFFFF;">Timestamp</th>
			      </tr>';

        -- Construct the message with error messages, timestamps, job names, and step names in an HTML table
        SELECT @message = @message + 
            '<tr>
				        <td style="border: 2px solid #8c0416;text-align:center;padding: 5px;">' + JobName + '</td>' +
				        '<td style="border: 2px solid #8c0416;text-align:center;padding: 5px;">' + StepName + '</td>' +
				        '<td style="border: 2px solid #8c0416;text-align:center;padding: 5px;">' + ErrorMessage + '</td>' +
				        '<td style="border: 2px solid #8c0416;text-align:center;padding: 5px;">' + CONVERT(NVARCHAR, ErrorTime, 120) + '</td>
			      </tr>'
        FROM @ErrorMessages;

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
