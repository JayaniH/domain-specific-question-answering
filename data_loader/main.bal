import ballerina/io;
import ballerinax/openai.embeddings;
import ballerinax/googleapis.sheets;
import ballerinax/pinecone.vector as pinecone;

configurable string sheetsAccessToken = ?;
configurable string sheetId = ?;
configurable string sheetName = ?;
configurable string openAIToken = ?;
configurable string pineconeKey = ?;
configurable string pineconeServiceUrl = ?;

const NAMESPACE = "SampleData";
const EMBEDDING_MODEL = "text-embedding-ada-002";

final embeddings:Client embeddingsClient = check new({auth: {token: openAIToken}});
final sheets:Client sheetsClient = check new({auth: {token: sheetsAccessToken}});
final pinecone:Client pineconeClient = check new({apiKey: pineconeKey}, serviceUrl = pineconeServiceUrl);

function getEmbedding(string text) returns float[]|error {
    embeddings:CreateEmbeddingResponse embeddingRes = check embeddingsClient->/embeddings.post({
        input: text,
        model: EMBEDDING_MODEL
    });
    return embeddingRes.data[0].embedding;
}

public function main() returns error?{
    // implement the logic to read the data from the google sheet and insert the embedding vectors to pinecone
    pinecone:Vector[] vectors = [];

    sheets:Range range = check sheetsClient->getRange(sheetId, sheetName, "A2:B");

    foreach any[] row in range.values {
        string title = row[0].toString();
        string content = row[1].toString();
        float[] embedding = check getEmbedding(content);
        vectors.push({id: title, values: embedding, metadata: {"content": content}});
    }

    _ = check pineconeClient->/vectors/upsert.post({
        namespace: NAMESPACE,
        vectors
    });
    
    io:println("Successfully inserted the data to pinecone.");
}