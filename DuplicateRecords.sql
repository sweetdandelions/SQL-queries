SELECT YourColumnName, COUNT(*) AS DuplicateCount
FROM YourTableName
GROUP BY YourColumnName
HAVING COUNT(*) > 1;

------------------------------
SELECT CurrencyID,CurrencyDate,
    CASE
        WHEN CurrencyID = LAG(CurrencyID) OVER (ORDER BY CurrencyID) THEN 'Yes'
        ELSE 'No'
    END AS duplicate_value
FROM dbo.NewFactCurrencyRate
ORDER BY CurrencyID;

------------------------------

WITH DuplicatesCTE AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY YourColumnName ORDER BY YourPrimaryKeyColumn) AS RowNum
    FROM YourTableName
)
SELECT *
FROM DuplicatesCTE
WHERE RowNum > 1;
