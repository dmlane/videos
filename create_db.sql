CREATE TABLE program (
	id integer PRIMARY KEY AUTOINCREMENT,
	name text unique
);

CREATE TABLE series (
	id integer PRIMARY KEY AUTOINCREMENT,
	program_id integer,
	series_number integer,
	max_episodes integer,
	UNIQUE(program_id,series_number),
	constraint fk_program 
		foreign key (program_id)
		references Program(id)
		on delete cascade
);

CREATE TABLE episode (
	id integer PRIMARY KEY AUTOINCREMENT,
	series_id integer ,
	episode_number integer,
	status integer,
	UNIQUE(series_id,episode_number)
	constraint fk_series
		foreign key (series_id)
		references Series(id)
		on delete cascade
);

CREATE TABLE raw_file (
	id integer PRIMARY KEY AUTOINCREMENT,
	name varchar,
	video_length datetime,
	last_updated datetime,
	status integer
);

CREATE TABLE section (
	id integer PRIMARY KEY AUTOINCREMENT,
	episode_id integer,
	section_number integer,
	start_time datetime,
	end_time datetime,
	raw_file_id integer,
	last_updated datetime DEFAULT CURRENT_TIMESTAMP,
	status integer,
	UNIQUE(episode_id,section_number)
	constraint fk_episode
		foreign key (episode_id)
		references Episode(id)
		on delete cascade
	constraint fk_raw_file
		foreign key (raw_file_id)
		references Raw_file(id)
		on delete set null
);
create table status (
	table_name varchar,
	id integer,
	name varchar2,
	primary key (table_name,id)
	);
create table new_files (
	id integer PRIMARY KEY AUTOINCREMENT,
	name varchar unique,
	video_length datetime,
    last_updated datetime
	);
create view videos as select a.id program_id,a.name program_name,
	b.id series_id, b.series_number,b.max_episodes,
	c.id episode_id,c.episode_number,c.status episode_status,
	d.id section_id,d.section_number,d.start_time,d.end_time,d.last_updated,
	e.name file_name,e.video_length
	from program a
	left outer join series b on b.program_id=a.id
	left outer join episode c on c.series_id=b.id
	left outer join section d on d.episode_id=c.id
	left outer join raw_file e on e.id=d.raw_file_id;
create view orphan_mp4 as select a.* from raw_file a
	left outer join section b on a.id=a.raw_file_id
	where b.raw_file_id is null;


begin;
insert into status (table_name,id,name) values ('raw_file',0,'sitting in import and ready to process');
insert into status (table_name,id,name) values ('raw_file',1,'sitting in import and ready to split');
insert into status (table_name,id,name) values ('raw_file',2,'sitting in import and being split');
insert into status (table_name,id,name) values ('raw_file',3,'sitting in import, successfully split and ready to archive');
insert into status (table_name,id,name) values ('raw_file',4,'sitting in archive');
commit;
