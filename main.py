import os
from neo4j import GraphDatabase
from provided.scraper import fetch_html
from bs4 import BeautifulSoup
import requests
import json
import re
from dotenv import load_dotenv

# Neo4j connection details
load_dotenv()
NEO4J_URI = os.getenv("NEO4J_URI")
NEO4J_USER = os.getenv("NEO4J_USER")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD")

def get_driver():
    if not all([NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD]):
        raise RuntimeError("Neo4j environment variables are missing or not loaded")
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
    """Extracts structured graph data from text using an LLM."""
    prompt = f"""
You are an information extraction system.

Return ONLY valid JSON.
Do NOT include explanations or markdown.

Important rules:
- Do not invent information.
- If a value is not explicitly present, use null or an empty list.
- Do not use placeholder values like "string".

Extract structured data from list-based or navigational content.

Schema:
{{
  "project": {{
    "name": "text or null",
    "url": "text or null",
    "description": "text or null"
  }},
  "meetings": [
    {{
      "title": "text",
      "date": "ISO date string or null",
      "type": "text or null",
      "committee": {{
        "name": "text or null",
        "hasVotingPower": "true/false or null"
      }},
      "topics": [],
      "documents": [
        {{
          "title": "text",
          "type": "text or null",
          "url": "text or null"
        }}
      ],
      "statements": []
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
            "format": "json"
        }
    )

    result = response.json()
    raw_content = result.get("response", "")

    clean_json = re.search(r'\{.*\}', raw_content, re.DOTALL)
    if clean_json:
        return json.loads(clean_json.group(0))

    return json.loads(raw_content)



def write_graph_to_neo4j(data: dict):
    """Writes extracted LLM data into Neo4j, with defensive handling for missing or malformed fields."""

    if not isinstance(data, dict):
        raise ValueError("LLM output is not a dictionary")

    driver = get_driver()

    with driver.session() as session:

        # ---------- Project ----------
        project = data.get("project")
        if not isinstance(project, dict):
            raise ValueError("Project data is missing or invalid")

        project_name = project.get("name")
        if not project_name:
            raise ValueError("Project name is missing")

        session.run(
            """
            MERGE (p:Project {name: $name})
            SET p.url = $url,
                p.description = $description
            """,
            name=project_name,
            url=project.get("url"),
            description=project.get("description")
        )

        # ---------- Meetings ----------
        meetings = data.get("meetings")
        if not isinstance(meetings, list):
            return  # No meetings → nothing else to write

        for meeting in meetings:
            if not isinstance(meeting, dict):
                continue

            title = meeting.get("title")
            date = meeting.get("date")

            # Cannot safely identify a Meeting without these
            if not title or not date:
                continue

            session.run(
                """
                MATCH (p:Project {name: $project_name})
                MERGE (m:Meeting {title: $title, date: $date})
                SET m.type = $type
                MERGE (p)-[:HAS_MEETING]->(m)
                """,
                project_name=project_name,
                title=title,
                date=date,
                type=meeting.get("type")
            )

            # ---------- Committee ----------
            committee = meeting.get("committee")
            if isinstance(committee, dict) and committee.get("name"):
                session.run(
                    """
                    MATCH (m:Meeting {title: $title, date: $date})
                    MERGE (c:Committee {name: $name})
                    SET c.hasVotingPower = $hasVotingPower
                    MERGE (m)-[:HELD_BY]->(c)
                    """,
                    title=title,
                    date=date,
                    name=committee.get("name"),
                    hasVotingPower=committee.get("hasVotingPower")
                )

            # ---------- Topics ----------
            for topic in meeting.get("topics") or []:
                if not isinstance(topic, dict) or not topic.get("name"):
                    continue

                session.run(
                    """
                    MATCH (m:Meeting {title: $title, date: $date})
                    MERGE (t:Topic {name: $name})
                    SET t.category = $category
                    MERGE (m)-[:DISCUSSED]->(t)
                    """,
                    title=title,
                    date=date,
                    name=topic.get("name"),
                    category=topic.get("category")
                )

            # ---------- Documents ----------
            for doc in meeting.get("documents") or []:
                if not isinstance(doc, dict) or not doc.get("title"):
                    continue

                session.run(
                    """
                    MATCH (m:Meeting {title: $title, date: $date})
                    MERGE (d:Document {title: $doc_title})
                    SET d.url = $url,
                        d.type = $type
                    MERGE (m)-[:HAS_DOCUMENT]->(d)
                    """,
                    title=title,
                    date=date,
                    doc_title=doc.get("title"),
                    url=doc.get("url"),
                    type=doc.get("type")
                )

            # ---------- Statements ----------
            for stmt in meeting.get("statements") or []:
                if not isinstance(stmt, dict) or not stmt.get("text"):
                    continue

                session.run(
                    """
                    MATCH (m:Meeting {title: $title, date: $date})
                    CREATE (s:Statement {text: $text, speaker: $speaker})
                    MERGE (m)-[:RECORDED_STATEMENT]->(s)
                    """,
                    title=title,
                    date=date,
                    text=stmt.get("text"),
                    speaker=stmt.get("speaker")
                )

    driver.close()
    print("Data successfully written to Neo4j.")