-- drop table Customer;
CREATE TABLE Customer (
	-- tbl_id int AUTO_INCREMENT,
    	cust_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
    	fullname varchar(50) NOT NULL,
    	position varchar(30) NOT NULL,
    	start_date date NOT NULL
);

-- drop table Customer_History;
CREATE TABLE Customer_History (
	hist_id int AUTO_INCREMENT PRIMARY KEY,
    	cust_id int NOT NULL,
    	fullname varchar(50),
    	position varchar(30),
    	eff_start_date date,
    	eff_end_date date,
    	curr_flag char(1),
    	change_flag varchar(10),
    	change_version_id int
);

iNSERT INTO Customer (fullname, position, start_date)
VALUES
	    ("Dan Wilson", "Developer",  '2019-02-01'),
    	("Tara Karlston", "Junior Developer",  '2020-02-01'),
    	("Brenda Fulston", "CRM Developer", "2020-03-01"),
	    ("MIles Fulston", "CRM Integrator", "2020-04-01");
  
--------------------------------------------------------
--------------------------------------------------------

-- expire the records that exist in source
UPDATE Customer_History TGT, Customer SRC
SET eff_end_date = Subdate(start_date, 1), curr_flag = 'N' -- , change_flag = 'UPDATE'
WHERE TGT.cust_id = SRC.cust_id
AND (TGT.fullname <> SRC.fullname OR TGT.position <> SRC.position)
AND eff_end_date = '9999-12-31'
AND TGT.curr_flag = 'Y';

-- invalidate records that are deleted in source
UPDATE Customer_History TGT
SET eff_end_date = CURRENT_DATE(), curr_flag = 'N', change_flag = 'DELETE'
WHERE TGT.cust_id NOT IN (
	SELECT cust_id 
	FROM Customer)
AND TGT.curr_flag = 'Y';

-- add a new row for the changing records
INSERT INTO Customer_History
SELECT NULL,
	SRC.cust_id,
	SRC.fullname,
	SRC.position,
	SRC.start_date,
	'9999-12-31',
	'Y',
  'UPDATE', -- change_flag
  change_version_id + 1
FROM Customer_History TGT, Customer SRC
WHERE TGT.cust_id = SRC.cust_id
AND (TGT.fullname <> SRC.fullname OR TGT.position <> SRC.position)
AND EXISTS(
	SELECT * FROM Customer_History CH
	WHERE SRC.cust_id = CH.cust_id
	AND TGT.eff_end_date = Subdate(start_date, 1)
	AND NOT EXISTS(
		SELECT *
		FROM Customer_History CH2
		WHERE SRC.cust_id = CH2.cust_id
		AND CH2.eff_end_date = '9999-12-31'));
        
-- add new records
INSERT INTO Customer_History
SELECT NULL,
	cust_id,
	fullname,
	position,
	start_date,
	'9999-12-31',
	'Y',
  'INSERT',
   1
FROM Customer
WHERE cust_id NOT IN(
	SELECT CH2.cust_id
	FROM Customer_History CH, Customer CH2
	WHERE CH.cust_id = CH2.cust_id);
