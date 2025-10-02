const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3001;

app.use(cors());
app.use(express.json());

const pool = new Pool({
    user: process.env.DB_USER || 'dailylog',
    host: process.env.DB_HOST || 'localhost',
    database: process.env.DB_NAME || 'daily_log',
    password: process.env.DB_PASSWORD || 'dailylog123',
    port: process.env.DB_PORT || 5432,
});

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'OK', timestamp: new Date() });
});

// Get all entries
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
        res.json({ entries: result.rows, count: result.rowCount });
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: 'Failed to fetch entries' });
    }
});

// Create entry
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
        console.error('Error:', err);
        res.status(500).json({ error: 'Failed to create entry' });
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
        console.error('Error:', err);
        res.status(500).json({ error: 'Failed to delete entry' });
    }
});

// Get statistics
app.get('/api/statistics', async (req, res) => {
    try {
        const { user_id = 1 } = req.query;
        
        const totalEntries = await pool.query(
            'SELECT COUNT(*) as count FROM log_entries WHERE user_id = $1',
            [user_id]
        );
        
        const topActivities = await pool.query(`
            SELECT description, COUNT(*) as count
            FROM log_entries
            WHERE user_id = $1
            GROUP BY description
            ORDER BY count DESC
            LIMIT 10
        `, [user_id]);
        
        const totalDays = await pool.query(`
            SELECT COUNT(DISTINCT entry_date) as count
            FROM log_entries
            WHERE user_id = $1
        `, [user_id]);
        
        res.json({
            total_entries: parseInt(totalEntries.rows[0].count),
            total_days: parseInt(totalDays.rows[0].count),
            top_activities: topActivities.rows
        });
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: 'Failed to fetch statistics' });
    }
});

app.listen(port, () => {
    console.log(`Daily Log API server running on port ${port}`);
});

module.exports = app;
