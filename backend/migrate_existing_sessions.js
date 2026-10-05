const db = require('./config/db.js');

const migrateExistingSessions = async () => {
    try {
        console.log('Fetching existing sessions...');
        const res = await db.query(`
            SELECT id, COALESCE(start_time, session_start, created_at) as event_date, session_code
            FROM shunting_sessions
            ORDER BY COALESCE(start_time, session_start, created_at) ASC
        `);

        const sessions = res.rows;
        console.log(`Found ${sessions.length} sessions to process.`);

        const dateCounters = {};
        let updatedCount = 0;

        for (const session of sessions) {
            if (!session.event_date) continue;

            const d = new Date(session.event_date);
            const year = d.getFullYear();
            const month = String(d.getMonth() + 1).padStart(2, '0');
            const day = String(d.getDate()).padStart(2, '0');
            const dateStr = `${year}${month}${day}`;
            const dateKey = `${year}-${month}-${day}`;

            // Check if it already matches the new format
            const isNewFormat = session.session_code && session.session_code.startsWith(`S-${dateStr}`);
            
            if (!dateCounters[dateKey]) {
                dateCounters[dateKey] = 0;
            }

            dateCounters[dateKey]++;
            const seqNumber = dateCounters[dateKey];
            const newSessionCode = `S-${dateStr}${String(seqNumber).padStart(4, '0')}`;

            if (session.session_code !== newSessionCode) {
                await db.query(`
                    UPDATE shunting_sessions
                    SET session_code = $1, session_number = $1
                    WHERE id = $2
                `, [newSessionCode, session.id]);
                updatedCount++;
            }
        }

        console.log(`Updated ${updatedCount} sessions with the new format.`);

        console.log('Updating session_daily_sequences table...');
        for (const [dateKey, maxSeq] of Object.entries(dateCounters)) {
            await db.query(`
                INSERT INTO session_daily_sequences (sequence_date, last_sequence)
                VALUES ($1, $2)
                ON CONFLICT (sequence_date) 
                DO UPDATE SET last_sequence = EXCLUDED.last_sequence
                WHERE session_daily_sequences.last_sequence < EXCLUDED.last_sequence
            `, [dateKey, maxSeq]);
        }
        
        console.log('Migration of existing sessions completed successfully.');
    } catch (e) {
        console.error('Migration failed:', e);
    } finally {
        process.exit(0);
    }
};

migrateExistingSessions();
