-- Create table User
CREATE TABLE User (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL
);

-- Insert values into User
INSERT INTO User (id, name, email)
VALUES
    (1, 'john_doe', 'john@example.com'), -- Inserting John Doe
    (2, 'jane_doe', 'jane@example.com'); -- Inserting Jane Doe
