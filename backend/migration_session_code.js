const db = require('./config/db.js');

const migrate = async () => {
    try {
        await db.query(`
            CREATE TABLE IF NOT EXISTS session_daily_sequences (
                sequence_date DATE PRIMARY KEY,
                last_sequence INT NOT NULL DEFAULT 0
            );
        `);
        
        await db.query(`
            CREATE OR REPLACE FUNCTION generate_session_code_func()
            RETURNS TRIGGER AS $$
            DECLARE
                next_seq INT;
                today_date DATE;
                new_session_code VARCHAR;
            BEGIN
                today_date := CURRENT_DATE;

                INSERT INTO session_daily_sequences (sequence_date, last_sequence)
                VALUES (today_date, 1)
                ON CONFLICT (sequence_date) 
                DO UPDATE SET last_sequence = session_daily_sequences.last_sequence + 1
                RETURNING last_sequence INTO next_seq;

                -- Format: S-YYYYMMDD0001
                new_session_code := 'S-' || TO_CHAR(today_date, 'YYYYMMDD') || LPAD(next_seq::text, 4, '0');
                
                NEW.session_code := new_session_code;
                NEW.session_number := new_session_code;

                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
        `);

        await db.query(`DROP TRIGGER IF EXISTS set_session_code_trigger ON shunting_sessions;`);

        await db.query(`
            CREATE TRIGGER set_session_code_trigger
            BEFORE INSERT ON shunting_sessions
            FOR EACH ROW
            EXECUTE FUNCTION generate_session_code_func();
        `);

        console.log('Migration successful');
    } catch (e) {
        console.error('Migration failed:', e);
    } finally {
        process.exit(0);
    }
};

migrate();
