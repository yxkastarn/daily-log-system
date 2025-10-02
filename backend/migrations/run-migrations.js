const { Client } = require('pg');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

async function runMigrations() {
    const client = new Client({
        user: process.env.DB_USER || 'dailylog',
        host: process.env.DB_HOST || 'localhost',
        database: process.env.DB_NAME || 'daily_log',
        password: process.env.DB_PASSWORD || 'dailylog123',
        port: process.env.DB_PORT || 5432,
    });

    try {
        console.log('Connecting to database...');
        await client.connect();
        console.log('Connected successfully!');

        // Read the schema file
        const schemaPath = path.join(__dirname, '../../database/schema.sql');
        const schema = fs.readFileSync(schemaPath, 'utf8');

        console.log('Running migrations...');
        await client.query(schema);
        console.log('✓ Migrations completed successfully!');

        // Verify tables
        const result = await client.query(`
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_type = 'BASE TABLE'
            ORDER BY table_name
        `);

        console.log('\n✓ Created tables:');
        result.rows.forEach(row => {
            console.log(`  - ${row.table_name}`);
        });

        // Verify views
        const viewsResult = await client.query(`
            SELECT table_name 
            FROM information_schema.views 
            WHERE table_schema = 'public'
            ORDER BY table_name
        `);

        console.log('\n✓ Created views:');
        viewsResult.rows.forEach(row => {
            console.log(`  - ${row.table_name}`);
        });

    } catch (err) {
        console.error('Error running migrations:', err);
        process.exit(1);
    } finally {
        await client.end();
        console.log('\nDatabase connection closed.');
    }
}

runMigrations();