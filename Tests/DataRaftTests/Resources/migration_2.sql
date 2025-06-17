-- Create table Device
CREATE TABLE Device (
    id INTEGER PRIMARY KEY,
    model TEXT NOT NULL
);

-- Insert values into Device
INSERT INTO Device (id, model)
VALUES
    (1, 'iPhone 14'), -- Inserting iPhone 14
    (2, 'iPhone 15'); -- Inserting iPhone 15
