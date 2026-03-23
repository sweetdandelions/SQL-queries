<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
				xmlns:xs="http://www.w3.org/2001/XMLSchema"
				version="2.0">

	<!-- Remove empty rows -->
	<xsl:template match="tr[td/text()='']"/>

	<xsl:template match="/">
		<html>
			<head>
				<style>
					table {
						border-collapse: collapse;
						width: 100%;
					}

					th {
						background-color: #1f3b6b;
						color: white;
						text-align: center;
						padding: 5px;
						border: 2px solid black;
						font-family: sans-serif;
						font-size: 14px;
					}

					td {
						padding: 5px;
						border: 2px solid black;
						text-align: center;
						font-family: sans-serif;
						font-size: 13px;
					}

					/* Status colors */
					.Waiting {
						background-color: #f5d572;
						color: black;
						font-weight: bold;
					}

					.Running {
						background-color: #639bd8;
						color: white;
						font-weight: bold;
					}

					.Completed {
						background-color: #9ae7ac;
						color: black;
						font-weight: bold;
					}

					.Failed {
						background-color: #d80d21;
						color: white;
						font-weight: bold;
					}

					.Failed-Stuck {
						background-color: #aa1e2c;
						color: white;
						font-weight: bold;
					}

					.SLA-Breach {
						background-color: #efb6a7;
						color: black;
						font-weight: bold;
					}

					h2 {
						font-family: sans-serif;
						color: #366ac5;
						border-bottom: 2px solid #366ac5;
						padding-bottom: 5px;
						font-size: 16px;
						margin-top: 30px;
					}
				</style>
			</head>
			<body>
				<xsl:if test="/DocumentRoot/Document/Data">

					<!-- Header -->
					<h2>
						Job Execution Status -
						<xsl:value-of select="format-date(current-date(), '[Y0001]-[M01]-[D01] ([FNn])')"/>
					</h2>
					
					<!-- Group pipelines -->
					<xsl:for-each-group select="/DocumentRoot/Document/Data"
						group-by="
							if (status = 'Failed') then 'Failed'
								else if (
									(
										starts-with(occurrence, 'Daily')
										or (
											starts-with(occurrence, 'Weekly')
											and contains(occurrence,
												substring(
													format-date(xs:date(substring(expected_start_sla_dt, 1, 10)), '[FNn]'),
												1, 3))
										)
										or (
											starts-with(occurrence, 'Monthly')
											and contains(occurrence,
												string(day-from-date(xs:date(substring(expected_start_sla_dt, 1, 10)))))
										)
										or (
											occurrence = 'Mon-Fri'
											and contains('Mon Tue Wed Thu Fri',
												substring(
													format-date(xs:date(substring(expected_start_sla_dt, 1, 10)), '[FNn]'),
												1, 3))
										)
									)
									and (
									(status = 'Waiting' and current-dateTime() > xs:dateTime(expected_start_sla_dt))
									or
									(status = 'Running' and current-dateTime() > xs:dateTime(expected_stop_sla_dt))
								)
								)
								then 'SLA Breach'
								else status
						">

						<!-- Sort groups -->
						<xsl:sort select="
							if (current-grouping-key() = 'Failed') then 1
							else if (current-grouping-key() = 'SLA Breach') then 2
							else if (current-grouping-key() = 'Running') then 3
							else if (current-grouping-key() = 'Completed') then 4
							else if (current-grouping-key() = 'Waiting') then 5
							else 6
						"/>

						<!-- Section header -->
						<h2>
							<xsl:value-of select="current-grouping-key()"/> (<xsl:value-of select="count(current-group())"/>)
						</h2>

						<!-- Table -->
						<table>
							<tr>
								<th>Pipeline Name</th>
								<th>Occurrence</th>
								<th>Status</th>
								<th>Starts At</th>
								<th>Completes By</th>
							</tr>
							
							<xsl:variable name="groupKey" select="current-grouping-key()"/>
							<!-- Rows -->
							<xsl:for-each select="current-group()">
								<tr>
									<!-- Pipeline Name -->
									<td>
										<xsl:value-of select="PKG_NM"/>
									</td>
									<!-- Occurrence (text: Daily / Weekly Wed / Monthly 15th) -->
									<td>
										<xsl:value-of select="occurrence"/>
									</td>
									<!-- Status -->
									<td>
										<xsl:attribute name="class">
											<xsl:choose>
												<xsl:when test="$groupKey='SLA Breach'">SLA-Breach</xsl:when>
												<xsl:when test="status='Waiting'">Waiting</xsl:when>
												<xsl:when test="status='Running'">Running</xsl:when>
												<xsl:when test="status='Completed'">Completed</xsl:when>
												<xsl:when test="status='Failed'">Failed</xsl:when>
												<xsl:when test="status='No data'">Failed-Stuck</xsl:when>
												<xsl:otherwise>Unknown</xsl:otherwise>
											</xsl:choose>
										</xsl:attribute>
										<xsl:value-of select="status"/>
									</td>

									<!-- Starts At -->
									<td>
										<xsl:value-of select="expected_start"/>
									</td>
									<!-- Completes By -->
									<td>
										<xsl:value-of select="expected_completion"/>
									</td>
								</tr>
							</xsl:for-each>
						</table>
					</xsl:for-each-group>
				</xsl:if>
			</body>
		</html>
	</xsl:template>
</xsl:stylesheet>
