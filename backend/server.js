const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const multer = require('multer');
const XLSX = require('xlsx');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3001;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Database connection
const pool = new Pool({
    user: process.env.DB_USER || 'dailylog',
    host: process.env.DB_HOST || 'localhost',
    database: process.env.DB_NAME || 'daily_log',
    password: process.env.DB_PASSWORD || 'dailylog123',
    port: process.env.DB_PORT || 5432,
});

// Test database connection
pool.query('SELECT NOW()', (err, res) => {
    if (err) {
        console.error('Database connection error:', err);
    } else {
        console.log('Database connected successfully');
    }
});

// Multer for file uploads
const upload = multer({ storage: multer.memoryStorage() });

// Helper functions
const calculateWorkHours = (entries, lunchHours = 0.5) => {
    if (entries.length === 0) return 0;
    
    let totalMinutes = 0;
    entries.forEach(entry => {
        if (entry.end_time) {
            const start = new Date(`2000-01-01 ${entry.start_time}`);
            const end = new Date(`2000-01-01 ${entry.end_time}`);
            const diff = (end - start) / (1000 * 60); // minutes
            totalMinutes += diff;
        }
    });
    
    const totalHours = totalMinutes / 60;
    return Math.max(0, totalHours - lunchHours);
};

// ===== ROUTES =====

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'OK', timestamp: new Date() });
});

// Get all entries with filters
app.get('/api/entries', async (req, res) => {
    try {
        const { user_id, start_date, end_date, limit = 100, offset = 0 } = req.query;
        
        let query = 'SELECT * FROM log_entries WHERE 1=1';
        const params = [];
        let paramCount = 1;
        
        if (user_id) {
            query += ` AND user_id = $${paramCount}`;
            params.push(user_id);
            paramCount++;
        }
        
        if (start_date) {
            query += ` AND entry_date >= $${paramCount}`;
            params.push(start_date);
            paramCount++;
        }
        
        if (end_date) {
            query += ` AND entry_date <= $${paramCount}`;
            params.push(end_date);
            paramCount++;
        }
        
        query += ` ORDER BY entry_date DESC, start_time DESC LIMIT $${paramCount} OFFSET $${paramCount + 1}`;
        params.push(limit, offset);
        
        const result = await pool.query(query, params);
        res.json({
            entries: result.rows,
            count: result.rowCount
        });
    } catch (err) {
        console.error('Error fetching entries:', err);
        res.status(500).json({ error: 'Failed to fetch entries' });
    }
});

// Get single entry
app.get('/api/entries/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const result = await pool.query('SELECT * FROM log_entries WHERE id = $1', [id]);
        
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Entry not found' });
        }
        
        res.json(result.rows[0]);
    } catch (err) {
        console.error('Error fetching entry:', err);
        res.status(500).json({ error: 'Failed to fetch entry' });
    }
});

// Create new entry
app.post('/api/entries', async (req, res) => {
    try {
        const { user_id = 1, entry_date, start_time, end_time, description } = req.body;
        
        if (!entry_date || !start_time || !description) {
            return res.status(400).json({ error: 'Missing required fields' });
        }
        
        const query = `
            INSERT INTO log_entries (user_id, entry_date, start_time, end_time, description)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
        `;
        
        const result = await pool.query(query, [user_id, entry_date, start_time, end_time, description]);
        res.status(201).json(result.rows[0]);
    } catch (err) {
        console.error('Error creating entry:', err);
        res.status(500).json({ error: 'Failed to create entry' });
    }
});

// Update entry
app.put('/api/entries/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const { entry_date, start_time, end_time, description } = req.body;
        
        const query = `
            UPDATE log_entries 
            SET entry_date = COALESCE($1, entry_date),
                start_time = COALESCE($2, start_time),
                end_time = COALESCE($3, end_time),
                description = COALESCE($4, description),
                updated_at = CURRENT_TIMESTAMP
            WHERE id = $5
            RETURNING *
        `;
        
        const result = await pool.query(query, [entry_date, start_time, end_time, description, id]);
        
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Entry not found' });
        }
        
        res.json(result.rows[0]);
    } catch (err) {
        console.error('Error updating entry:', err);
        res.status(500).json({ error: 'Failed to update entry' });
    }
});

// Delete entry
app.delete('/api/entries/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const result = await pool.query('DELETE FROM log_entries WHERE id = $1 RETURNING *', [id]);
        
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Entry not found' });
        }
        
        res.json({ message: 'Entry deleted successfully' });
    } catch (err) {
        console.error('Error deleting entry:', err);
        res.status(500).json({ error: 'Failed to delete entry' });
    }
});

// Get daily summary
app.get('/api/summaries/daily', async (req, res) => {
    try {
        const { date, user_id = 1 } = req.query;
        
        if (!date) {
            return res.status(400).json({ error: 'Date parameter required' });
        }
        
        const entriesQuery = `
            SELECT * FROM log_entries 
            WHERE entry_date = $1 AND user_id = $2
            ORDER BY start_time
        `;
        
        const entries = await pool.query(entriesQuery, [date, user_id]);
        const workHours = calculateWorkHours(entries.rows);
        
        res.json({
            date,
            entries: entries.rows,
            total_entries: entries.rowCount,
            work_hours: workHours.toFixed(2),
            lunch_hours: 0.5
        });
    } catch (err) {
        console.error('Error fetching daily summary:', err);
        res.status(500).json({ error: 'Failed to fetch daily summary' });
    }
});

// Get weekly summary
app.get('/api/summaries/weekly', async (req, res) => {
    try {
        const { start_date, user_id = 1 } = req.query;
        
        if (!start_date) {
            return res.status(400).json({ error: 'Start date parameter required' });
        }
        
        const query = `
            SELECT 
                entry_date,
                COUNT(*) as entry_count,
                MIN(start_time) as first_entry,
                MAX(end_time) as last_entry
            FROM log_entries
            WHERE entry_date >= $1 
            AND entry_date < $1::date + INTERVAL '7 days'
            AND user_id = $2
            GROUP BY entry_date
            ORDER BY entry_date
        `;
        
        const result = await pool.query(query, [start_date, user_id]);
        
        let totalHours = 0;
        for (const day of result.rows) {
            const dayEntries = await pool.query(
                'SELECT * FROM log_entries WHERE entry_date = $1 AND user_id = $2',
                [day.entry_date, user_id]
            );
            totalHours += calculateWorkHours(dayEntries.rows);
        }
        
        res.json({
            start_date,
            days: result.rows,
            total_work_hours: totalHours.toFixed(2),
            average_hours_per_day: (totalHours / 7).toFixed(2)
        });
    } catch (err) {
        console.error('Error fetching weekly summary:', err);
        res.status(500).json({ error: 'Failed to fetch weekly summary' });
    }
});

// Get monthly summary
app.get('/api/summaries/monthly', async (req, res) => {
    try {
        const { year, month, user_id = 1 } = req.query;
        
        if (!year || !month) {
            return res.status(400).json({ error: 'Year and month parameters required' });
        }
        
        const query = `
            SELECT 
                entry_date,
                COUNT(*) as entry_count
            FROM log_entries
            WHERE EXTRACT(YEAR FROM entry_date) = $1
            AND EXTRACT(MONTH FROM entry_date) = $2
            AND user_id = $3
            GROUP BY entry_date
            ORDER BY entry_date
        `;
        
        const result = await pool.query(query, [year, month, user_id]);
        
        let totalHours = 0;
        let workDays = 0;
        
        for (const day of result.rows) {
            const dayEntries = await pool.query(
                'SELECT * FROM log_entries WHERE entry_date = $1 AND user_id = $2',
                [day.entry_date, user_id]
            );
            const dayHours = calculateWorkHours(dayEntries.rows);
            if (dayHours > 0) {
                totalHours += dayHours;
                workDays++;
            }
        }
        
        res.json({
            year,
            month,
            days: result.rows,
            total_work_hours: totalHours.toFixed(2),
            work_days: workDays,
            average_hours_per_day: workDays > 0 ? (totalHours / workDays).toFixed(2) : 0
        });
    } catch (err) {
        console.error('Error fetching monthly summary:', err);
        res.status(500).json({ error: 'Failed to fetch monthly summary' });
    }
});

// Bulk import entries (JSON format)
app.post('/api/import/bulk', async (req, res) => {
    try {
        const { entries } = req.body;
        
        if (!Array.isArray(entries) || entries.length === 0) {
            return res.status(400).json({ error: 'Invalid entries array' });
        }
        
        let imported = 0;
        let errors = 0;
        
        const client = await pool.connect();
        
        try {
            await client.query('BEGIN');
            
            for (const entry of entries) {
                const { entry_date, start_time, end_time, description, user_id = 1 } = entry;
                
                if (!entry_date || !start_time || !description) {
                    errors++;
                    continue;
                }
                
                try {
                    await client.query(
                        'INSERT INTO log_entries (user_id, entry_date, start_time, end_time, description) VALUES ($1, $2, $3, $4, $5)',
                        [user_id, entry_date, start_time, end_time, description]
                    );
                    imported++;
                } catch (err) {
                    console.error(`Error importing entry:`, err);
                    errors++;
                }
            }
            
            await client.query('COMMIT');
            
            res.json({
                message: 'Bulk import completed',
                imported,
                errors,
                total: entries.length
            });
        } catch (err) {
            await client.query('ROLLBACK');
            throw err;
        } finally {
            client.release();
        }
    } catch (err) {
        console.error('Error in bulk import:', err);
        res.status(500).json({ error: 'Failed to import entries' });
    }
});

// Get statistics
app.get('/api/statistics', async (req, res) => {
    try {
        const { user_id = 1 } = req.query;
        
        // Total entries
        const totalEntries = await pool.query(
            'SELECT COUNT(*) as count FROM log_entries WHERE user_id = $1',
            [user_id]
        );
        
        // Most common activities
        const topActivities = await pool.query(`
            SELECT description, COUNT(*) as count
            FROM log_entries
            WHERE user_id = $1
            GROUP BY description
            ORDER BY count DESC
            LIMIT 10
        `, [user_id]);
        
        // Total days logged
        const totalDays = await pool.query(`
            SELECT COUNT(DISTINCT entry_date) as count
            FROM log_entries
            WHERE user_id = $1
        `, [user_id]);
        
        // Recent activity
        const recentActivity = await pool.query(`
            SELECT entry_date, COUNT(*) as entries
            FROM log_entries
            WHERE user_id = $1
            AND entry_date >= CURRENT_DATE - INTERVAL '30 days'
            GROUP BY entry_date
            ORDER BY entry_date DESC
        `, [user_id]);
        
        res.json({
            total_entries: parseInt(totalEntries.rows[0].count),
            total_days: parseInt(totalDays.rows[0].count),
            top_activities: topActivities.rows,
            recent_activity: recentActivity.rows
        });
    } catch (err) {
        console.error('Error fetching statistics:', err);
        res.status(500).json({ error: 'Failed to fetch statistics' });
    }
});

// Users endpoints
app.get('/api/users', async (req, res) => {
    try {
        const result = await pool.query('SELECT * FROM users ORDER BY id');
        res.json(result.rows);
    } catch (err) {
        console.error('Error fetching users:', err);
        res.status(500).json({ error: 'Failed to fetch users' });
    }
});

app.post('/api/users', async (req, res) => {
    try {
        const { name, email } = req.body;
        
        if (!name) {
            return res.status(400).json({ error: 'Name is required' });
        }
        
        const result = await pool.query(
            'INSERT INTO users (name, email) VALUES ($1, $2) RETURNING *',
            [name, email]
        );
        
        res.status(201).json(result.rows[0]);
    } catch (err) {
        console.error('Error creating user:', err);
        res.status(500).json({ error: 'Failed to create user' });
    }
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Unhandled error:', err);
    res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(port, () => {
    console.log(`Daily Log API server running on port ${port}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM signal received: closing HTTP server');
    pool.end(() => {
        console.log('Database pool closed');
    });
});

module.exports = app;