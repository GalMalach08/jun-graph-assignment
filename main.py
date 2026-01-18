from neo4j import GraphDatabase
from provided.scraper import fetch_html
from bs4 import BeautifulSoup
import requests
import json
import re

# Neo4j connection details
NEO4J_URI = "bolt://localhost:7687"
NEO4J_USER = "neo4j"
NEO4J_PASSWORD = "password123"

def get_driver():
    """Returns a new Neo4j driver instance."""
    return GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))

def get_clean_text(url: str) -> str:
    """Scrapes HTML and returns a cleaned string of text."""
    html = fetch_html(url)
    soup = BeautifulSoup(html, "html.parser")

    # Remove non-content tags
    for tag in soup(["script", "style", "noscript"]):
        tag.decompose()

    text = soup.get_text(separator=" ")
    return " ".join(text.split())

def extract_graph_data_with_llm(clean_text: str) -> dict:
    """Sends text to Ollama and returns a validated JSON dictionary."""
    prompt = f"""
You are an information extraction system. Return ONLY valid JSON.
Extract project, meetings, committees, topics, documents, and statements.

Schema:
{{
  "project": {{ "name": "string", "url": "string", "description": "string" }},
  "meetings": [
    {{
      "title": "string", "date": "string", "type": "string",
      "committee": {{ "name": "string", "hasVotingPower": "string" }},
      "topics": [ {{ "name": "string", "category": "string" }} ],
      "documents": [ {{ "title": "string", "type": "string", "url": "string" }} ],
      "statements": [ {{ "text": "string", "speaker": "string" }} ]
    }}
  ]
}}

Text:
\"\"\"
{clean_text}
\"\"\"
"""
    response = requests.post(
        "http://localhost:11434/api/generate",
        json={
            "model": "llama3.2:3b",
            "prompt": prompt,
            "stream": False,
            "format": "json" # Forces Ollama to output valid JSON
        }
    )

    result = response.json()
    raw_content = result.get("response", "")

    # Clean the response in case the LLM added markdown wrappers
    clean_json = re.search(r'\{.*\}', raw_content, re.DOTALL)
    if clean_json:
        return json.loads(clean_json.group(0))
    return json.loads(raw_content)

def write_graph_to_neo4j(data: dict):
    """Writes the extracted JSON data into the Neo4j graph database."""
    driver = get_driver()
    with driver.session() as session:

        # 2. Create Project Node
        project = data.get("project", {})
        session.run(
            """
            MERGE (p:Project {name: $name})
            SET p.url = $url, p.description = $description
            """,
            name=project.get("name"),
            url=project.get("url"),
            description=project.get("description")
        )

        # 3. Process Meetings and related entities
        for meeting in data.get("meetings", []):
            # Meeting Node
            session.run(
                """
                MATCH (p:Project {name: $project_name})
                MERGE (m:Meeting {title: $title, date: $date})
                SET m.type = $type
                MERGE (p)-[:HAS_MEETING]->(m)
                """,
                project_name=project.get("name"),
                title=meeting.get("title"),
                date=meeting.get("date"),
                type=meeting.get("type")
            )

            # Committee Node
            comm = meeting.get("committee")
            # Ensure comm is a dictionary and not None before calling .get()
            if isinstance(comm, dict) and comm.get("name"):
                session.run(
                    """
                    MATCH (m:Meeting {title: $meeting_title})
                    MERGE (c:Committee {name: $name})
                    SET c.hasVotingPower = $hasVotingPower
                    MERGE (m)-[:HELD_BY]->(c)
                    """,
                    meeting_title=meeting.get("title"),
                    name=comm.get("name"),
                    hasVotingPower=comm.get("hasVotingPower")
                )

            # Topics
            for topic in meeting.get("topics", []):
                session.run(
                    """
                    MATCH (m:Meeting {title: $meeting_title})
                    MERGE (t:Topic {name: $name})
                    SET t.category = $category
                    MERGE (m)-[:DISCUSSED]->(t)
                    """,
                    meeting_title=meeting.get("title"),
                    name=topic.get("name"),
                    category=topic.get("category")
                )

            # Documents (Added)
            for doc in meeting.get("documents", []):
                session.run(
                    """
                    MATCH (m:Meeting {title: $meeting_title})
                    MERGE (d:Document {title: $title})
                    SET d.url = $url, d.type = $type
                    MERGE (m)-[:HAS_DOCUMENT]->(d)
                    """,
                    meeting_title=meeting.get("title"),
                    title=doc.get("title"),
                    url=doc.get("url"),
                    type=doc.get("type")
                )

            # Statements (Added)
            for stmt in meeting.get("statements", []):
                session.run(
                    """
                    MATCH (m:Meeting {title: $meeting_title})
                    CREATE (s:Statement {text: $text, speaker: $speaker})
                    MERGE (m)-[:RECORDED_STATEMENT]->(s)
                    """,
                    meeting_title=meeting.get("title"),
                    text=stmt.get("text"),
                    speaker=stmt.get("speaker")
                )

    driver.close()
    print("Graph successfully written to Neo4j!")
