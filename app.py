from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware

# Importing your logic from main.py
from main import (
    get_clean_text,
    extract_graph_data_with_llm,
    write_graph_to_neo4j,
)

app = FastAPI(title="Knowledge Graph Builder")

# Enable CORS for frontend communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Data Models ---

class UrlRequest(BaseModel):
    url: str

class ExtractRequest(BaseModel):
    clean_text: str
    max_chars: int | None = None


class GraphRequest(BaseModel):
    data: dict

# --- API Endpoints ---

@app.post("/scrape")
def scrape(req: UrlRequest):
    """Fetches HTML and returns cleaned text from the given URL."""
    try:
        text = get_clean_text(req.url)
        return { "clean_text": text }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    
@app.post("/extract")
def extract(req: ExtractRequest):
    """Processes text with LLM to extract structured graph data."""
    try:
        clean_text = req.clean_text

        # Optional character limit to improve performance and stability
        if req.max_chars is not None:
            clean_text = clean_text[:req.max_chars]

        data = extract_graph_data_with_llm(clean_text)
        return data

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"LLM Extraction failed: {str(e)}"
        )



@app.post("/write-graph")
def write_graph(req: GraphRequest):
    """Saves the structured data into Neo4j database."""
    try:
        write_graph_to_neo4j(req.data)
        # testNeo4jConnection()
        return {
            "status": "success",
            "neo4j_url": "http://localhost:7474" # Default Neo4j Browser URL
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Neo4j Write failed: {str(e)}")
