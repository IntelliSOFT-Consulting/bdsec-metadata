-- ---------------------------------------------------------------------------------------------------------------------
-- void default ORs ["General OT", "Orthopaedic OT",]
UPDATE location
    SET retired = 1
    WHERE name IN ("General OT", "Orthopaedic OT");

SET @parent_location_id = (SELECT location_id FROM location WHERE name='Bahmni Hospital');

SET @or_location_tag_id = (SELECT location_tag_id FROM location_tag WHERE name='Operation Theater');

INSERT IGNORE INTO location (name, description, uuid, creator, date_created, retired, parent_location)
    VALUES  ("OR I", "OR I", UUID(), 1, NOW(), 0, @parent_location_id),
            ("OR II", "OR II", UUID(), 1, NOW(), 0, @parent_location_id),
            ("OR III", "OR III", UUID(), 1, NOW(), 0, @parent_location_id);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id)
    VALUES  ((SELECT location_id FROM location WHERE name='OR I'), @or_location_tag_id),
            ((SELECT location_id FROM location WHERE name='OR II'), @or_location_tag_id),
            ((SELECT location_id FROM location WHERE name='OR III'), @or_location_tag_id);

-- ---------------------------------------------------------------------------------------------------------------------
INSERT IGNORE INTO surgical_appointment_attribute_type (name, description, format, date_created, creator, retired, uuid, sort_weight)
    VALUES ('Equipment', 'Equipment', 'java.lang.String', NOW(), 1, 0, '9d98094a-492f-49da-ba63-e128f1b1bed9', 11),
            ('Complications', 'Complications', 'java.lang.String', NOW(), 1, 0, '6b276fcf-0e7c-43b8-ad9f-41d8d8ba5682', 12),
            ('Discharge Notes', 'Discharge Notes', 'java.lang.String', NOW(), 1, 0, '339abca0-ff60-4706-95c6-acdc3c4d66b3', 13),
            ('Disposables', 'Disposables', 'java.lang.String', NOW(), 1, 0, '412d4037-7a53-4701-9fc0-c21ab862dac5', 14);


-- ---------------------------------------------------------------------------------------------------------------------
-- void default wards [Emergency, General Ward, Pediatric Ward]
UPDATE location
    SET retired = 1
    WHERE name IN ("Emergency", "Emergency Ward",  "General Ward", "General Ward Room-1", "General Ward Room-2", "Pediatric Ward", "Pediatric Ward Room-1");


SET @location_tag_id = (select location_tag_id from location_tag where name='Admission Location' LIMIT 1);

-- BED TYPES
INSERT IGNORE INTO bed_type (bed_type_id, name, display_name, description)
    VALUES  (1, 'IPD', 'In patient',  'IPD'),
            (2, 'VIP', 'VIP',  'VIP'),
            (3, 'Recovery', 'Recovery', 'Recovery');
--  INITALIZE BED TYPE IDs
SET @ipd_bed_type_id = (SELECT bed_type_id FROM bed_type WHERE name = 'IPD' LIMIT 1);
SET @vip_bed_type_id = (SELECT bed_type_id FROM bed_type WHERE name = 'VIP' LIMIT 1);
SET @recovery_bed_type_id = (SELECT bed_type_id FROM bed_type WHERE name = 'Recovery' LIMIT 1);

-- IPD WARD
INSERT IGNORE INTO location (name, description, retired, uuid, date_created, creator)
    VALUES('IPD Ward', 'in-patient ward', 0, UUID(), NOW(), 1);

SET @parent_location_id = (SELECT location_id FROM location WHERE name='IPD Ward' LIMIT 1);

-- IPD WARD I
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('IPD Ward I', 'First IPD ward', 0, UUID(), @parent_location_id, NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='IPD Ward I' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
-- insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (1,'IPD-0001', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (2,'IPD-0004', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (3,'IPD-0002', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (4,'IPD-0003', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (5,'IPD-0005', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (1,@location_id, 1, 1, 1),
            (2,@location_id, 1, 2, 2),
            (3,@location_id, 1, 3, 3),
            (4,@location_id, 1, 4, 4),
            (5,@location_id, 1, 5, 5);



-- IPD WARD II
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('IPD Ward II', 'Second IPD ward', 0, UUID(), @parent_location_id,  NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='IPD Ward II' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
-- insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (6,'IPD-0006', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (7,'IPD-0007', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (8,'IPD-0008', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (9,'IPD-0009', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (10,'IPD-0010', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (6,@location_id, 1, 1, 6),
            (7,@location_id, 1, 2, 7),
            (8,@location_id, 1, 3, 8),
            (9,@location_id, 1, 4, 9),
            (10,@location_id, 1, 5,10);


-- IPD WARD III
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('IPD Ward III', 'Third IPD ward', 0, UUID(), @parent_location_id, NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='IPD Ward III' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
-- insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (11,'IPD-0011', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (12,'IPD-0012', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (13,'IPD-0013', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (14,'IPD-0014', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (15,'IPD-0015', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (11,@location_id, 1, 1, 11),
            (12,@location_id, 1, 2, 12),
            (13,@location_id, 1, 3, 13),
            (14,@location_id, 1, 4, 14),
            (15,@location_id, 1, 5, 15);


-- IPD WARD IV
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('IPD Ward IV', 'Fourth IPD ward', 0, UUID(), @parent_location_id, NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='IPD Ward IV' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
-- insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (16,'IPD-0016', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (17,'IPD-0017', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (18,'IPD-0018', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (19,'IPD-0019', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (20,'IPD-0020', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (16,@location_id, 1, 1, 16),
            (17,@location_id, 1, 2, 17),
            (18,@location_id, 1, 3, 18),
            (19,@location_id, 1, 4, 19),
            (20,@location_id, 1, 5, 20);


-- IPD WARD V
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('IPD Ward V', 'Fifth IPD ward', 0, UUID(), @parent_location_id, NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='IPD Ward V' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
-- insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (21,'IPD-0021', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (22,'IPD-0022', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (23,'IPD-0023', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (24,'IPD-0024', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1),
            (25,'IPD-0025', 'AVAILABLE', @ipd_bed_type_id, UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (21,@location_id, 1, 1, 21),
            (22,@location_id, 1, 2, 22),
            (23,@location_id, 1, 3, 23),
            (24,@location_id, 1, 4, 24),
            (25,@location_id, 1, 5, 25);



-- VIP WARD
INSERT IGNORE INTO location (name, description, retired, uuid, date_created, creator)
    VALUES('VIP Ward', 'vip ward', 0, UUID(), NOW(), 1);

SET @parent_location_id = (SELECT location_id FROM location WHERE name='VIP Ward' LIMIT 1);


-- VIP WARD I
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('VIP Ward I', 'First VIP ward', 0, UUID(), @parent_location_id, NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='VIP Ward I' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
-- insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (26,'VIP-0001', 'AVAILABLE',@vip_bed_type_id , UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (26,@location_id, 1, 1, 26);

-- VIP WARD II
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('VIP Ward II', 'Second VIP ward', 0, UUID(), @parent_location_id, NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='VIP Ward II' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
-- insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (27,'VIP-0002', 'AVAILABLE',@vip_bed_type_id , UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (27,@location_id, 1, 1, 27);

-- VIP WARD III
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('VIP Ward III', 'Third VIP ward', 0, UUID(), @parent_location_id, NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='VIP Ward III' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
--  insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (28,'VIP-0003', 'AVAILABLE',@vip_bed_type_id , UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (28,@location_id, 1, 1, 28);

-- VIP WARD IV
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('VIP Ward IV', 'Fourth VIP ward', 0, UUID(), @parent_location_id, NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='VIP Ward IV' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
--  insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (29,'VIP-0004', 'AVAILABLE',@vip_bed_type_id , UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (29,@location_id, 1, 1, 29);


-- RECOVERY WARD
INSERT IGNORE INTO location (name, description, retired, uuid, date_created, creator)
    VALUES('Recovery Ward', 'recovery ward', 0, UUID(), NOW(), 1);

SET @parent_location_id = (SELECT location_id FROM location WHERE name='Recovery Ward' LIMIT 1);


-- REC. WARD I
INSERT IGNORE INTO location (name, description, retired, uuid, parent_location,date_created, creator)
    VALUES ('Recovery Ward I', 'First Recovery ward', 0, UUID(), @parent_location_id, NOW(), 1);
SET @location_id = (SELECT location_id FROM location WHERE name='Recovery Ward I' LIMIT 1);

INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@parent_location_id, @location_tag_id);
INSERT IGNORE INTO location_tag_map (location_id, location_tag_id) VALUES (@location_id, @location_tag_id);
-- insert beds
INSERT IGNORE INTO bed (bed_id, bed_number, status, bed_type_id, uuid, voided, date_created, creator)
    VALUES  (30,'REC-0001', 'AVAILABLE',@recovery_bed_type_id, UUID(), false, NOW(), 1),
            (31,'REC-0002', 'AVAILABLE',@recovery_bed_type_id, UUID(), false, NOW(), 1),
            (32,'REC-0004', 'AVAILABLE',@recovery_bed_type_id, UUID(), false, NOW(), 1),
            (33,'REC-0003', 'AVAILABLE',@recovery_bed_type_id, UUID(), false, NOW(), 1),
            (34,'REC-0005', 'AVAILABLE',@recovery_bed_type_id, UUID(), false, NOW(), 1),
            (35,'REC-0006', 'AVAILABLE',@recovery_bed_type_id, UUID(), false, NOW(), 1);
-- arrange beds
INSERT IGNORE bed_location_map(bed_location_map_id, location_id, bed_row_number, bed_column_number, bed_id)
    VALUES  (30,@location_id, 1, 1, 30),
            (31,@location_id, 1, 2, 31),
            (32,@location_id, 1, 3, 32),
            (33,@location_id, 1, 4, 33),
            (34,@location_id, 1, 5, 34),
            (35,@location_id, 1, 6, 35);


-- Script to Set all drugs Selable
INSERT INTO concept_attribute ( concept_id, attribute_type_id, value_reference, uuid, creator, date_created, changed_by, date_changed, voided, voided_by, date_voided, void_reason
) SELECT concept_id, 1, 'true', UUID(), 4, '2024-12-16 07:53:15', NULL, NULL, 0, NULL, NULL, NULL FROM drug ;

-- Delete duplicate drugs in concept_attribute table
DELETE FROM concept_attribute WHERE concept_attribute_id NOT IN (
    SELECT * FROM (
        SELECT MIN(concept_attribute_id)
        FROM concept_attribute
        GROUP BY concept_id
    ) AS subquery
);

-- Removed default Bahmni forms

UPDATE form
SET retired = 1,
    retired_by = 1,           -- adjust to correct user_id from `users` table
    date_retired = NOW(),
    retired_reason = 'not used'
WHERE name IN (
    'Admission Letter',
    'Death Note',
    'Diabetes Progress',
    'Diabetes Intake',
    'Follow Up',
    'History and Examination',
    'Hypertension Intake',
    'Hypertension Progress',
    'Immunization Incident Record',
    'Malaria',
    'Obstetrics and Gynaecology',
    'Orthopaedic Examination',
    'Referral letter',
    'Second Vitals',
    'Under Treatment and Fitness Certificate',
    'Vitals',
    'Theatre Checklist',
    'Vitals_Form2',
    'Worth 4 Dot Test'
);




