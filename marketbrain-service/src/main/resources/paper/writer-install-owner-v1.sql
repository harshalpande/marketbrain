GRANT CREATE ON SCHEMA public TO marketbrain_paper_review_helper;
ALTER FUNCTION public.paper_review_lock(text,bigint,bigint) OWNER TO marketbrain_paper_review_helper;
ALTER FUNCTION public.paper_review_record(text,bigint,bigint,text,text) OWNER TO marketbrain_paper_review_helper;
REVOKE CREATE ON SCHEMA public FROM marketbrain_paper_review_helper;
GRANT EXECUTE ON FUNCTION public.paper_review_lock(text,bigint,bigint),public.paper_review_record(text,bigint,bigint,text,text)
 TO marketbrain_paper_review_writer;
