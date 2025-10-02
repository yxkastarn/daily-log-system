-- Daily Log System Database Schema
-- PostgreSQL 14+

DROP TABLE IF EXISTS daily_summaries CASCADE;
DROP TABLE IF EXISTS log_entries CASCADE;
DROP TABLE IF EXISTS projects CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Users table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Projects table
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Log entries table
CREATE TABLE log_entries (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entry_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME,
    description TEXT NOT NULL,
    project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Daily summaries table
CREATE TABLE daily_summaries (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entry_date DATE NOT NULL,
    total_hours DECIMAL(4,2),
    lunch_hours DECIMAL(3,2) DEFAULT 0.5,
    work_hours DECIMAL(4,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, entry_date)
);

-- Indexes
CREATE INDEX idx_log_entries_user_date ON log_entries(user_id, entry_date);
CREATE INDEX idx_log_entries_date ON log_entries(entry_date);
CREATE INDEX idx_daily_summaries_user_date ON daily_summaries(user_id, entry_date);

-- Create default user
INSERT INTO users (name, email) VALUES ('Petter Sandgren', 'petter@example.com');

-- Function to calculate work hours
CREATE OR REPLACE FUNCTION calculate_work_hours(
    p_entry_date DATE,
    p_user_id INTEGER DEFAULT 1,
    p_lunch_hours DECIMAL DEFAULT 0.5
) RETURNS DECIMAL AS $$
DECLARE
    v_total_minutes INTEGER := 0;
    v_entry RECORD;
BEGIN
    FOR v_entry IN 
        SELECT start_time, end_time 
        FROM log_entries 
        WHERE entry_date = p_entry_date 
        AND user_id = p_user_id
        AND end_time IS NOT NULL
    LOOP
        v_total_minutes := v_total_minutes + 
            EXTRACT(EPOCH FROM (v_entry.end_time - v_entry.start_time)) / 60;
    END LOOP;
    
    RETURN GREATEST(0, (v_total_minutes / 60.0) - p_lunch_hours);
END;
$$ LANGUAGE plpgsql;

-- Function to update daily summary
CREATE OR REPLACE FUNCTION update_daily_summary() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO daily_summaries (user_id, entry_date, work_hours)
    VALUES (
        NEW.user_id,
        NEW.entry_date,
        calculate_work_hours(NEW.entry_date, NEW.user_id)
    )
    ON CONFLICT (user_id, entry_date) 
    DO UPDATE SET 
        work_hours = calculate_work_hours(NEW.entry_date, NEW.user_id),
        updated_at = CURRENT_TIMESTAMP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update daily summaries
CREATE TRIGGER trigger_update_daily_summary
AFTER INSERT OR UPDATE OR DELETE ON log_entries
FOR EACH ROW
EXECUTE FUNCTION update_daily_summary();

-- Views for Grafana
CREATE OR REPLACE VIEW vw_daily_hours AS
SELECT 
    entry_date as time,
    user_id,
    u.name as user_name,
    work_hours,
    total_hours,
    lunch_hours
FROM daily_summaries ds
JOIN users u ON ds.user_id = u.id
ORDER BY entry_date DESC;

CREATE OR REPLACE VIEW vw_activity_frequency AS
SELECT 
    description,
    COUNT(*) as frequency,
    COUNT(DISTINCT entry_date) as days_count,
    MIN(entry_date) as first_occurrence,
    MAX(entry_date) as last_occurrence
FROM log_entries
GROUP BY description
ORDER BY frequency DESC;

CREATE OR REPLACE VIEW vw_weekly_summary AS
SELECT 
    DATE_TRUNC('week', entry_date) as week_start,
    user_id,
    u.name as user_name,
    SUM(work_hours) as total_hours,
    COUNT(DISTINCT entry_date) as work_days,
    AVG(work_hours) as avg_hours_per_day
FROM daily_summaries ds
JOIN users u ON ds.user_id = u.id
GROUP BY DATE_TRUNC('week', entry_date), user_id, u.name
ORDER BY week_start DESC;

CREATE OR REPLACE VIEW vw_monthly_summary AS
SELECT 
    DATE_TRUNC('month', entry_date) as month_start,
    EXTRACT(YEAR FROM entry_date) as year,
    EXTRACT(MONTH FROM entry_date) as month,
    user_id,
    u.name as user_name,
    SUM(work_hours) as total_hours,
    COUNT(DISTINCT entry_date) as work_days,
    AVG(work_hours) as avg_hours_per_day
FROM daily_summaries ds
JOIN users u ON ds.user_id = u.id
GROUP BY DATE_TRUNC('month', entry_date), 
         EXTRACT(YEAR FROM entry_date),
         EXTRACT(MONTH FROM entry_date),
         user_id, u.name
ORDER BY month_start DESC;

CREATE OR REPLACE VIEW vw_recent_activity AS
SELECT 
    entry_date,
    start_time,
    end_time,
    description,
    user_id,
    u.name as user_name,
    CASE 
        WHEN end_time IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (end_time - start_time)) / 3600.0
        ELSE NULL 
    END as duration_hours
FROM log_entries le
JOIN users u ON le.user_id = u.id
WHERE entry_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY entry_date DESC, start_time DESC;

CREATE OR REPLACE VIEW vw_hourly_distribution AS
SELECT 
    EXTRACT(HOUR FROM start_time) as hour,
    COUNT(*) as activity_count,
    COUNT(DISTINCT entry_date) as days_with_activity
FROM log_entries
GROUP BY EXTRACT(HOUR FROM start_time)
ORDER BY hour;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dailylog;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO dailylog;
GRANT ALL PRIVILEGES ON DATABASE daily_log TO dailylog;