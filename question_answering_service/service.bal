import ballerina/http;
import ballerina/regex;
import ballerinax/openai.embeddings;
import ballerinax/openai.text;
import ballerinax/pinecone.vector as pinecone;

configurable string openAIToken = ?;
configurable string pineconeKey = ?;
configurable string pineconeServiceUrl = ?;

final text:Client openAIText = check new ({auth: {token: openAIToken}});
final embeddings:Client openaiEmbeddings = check new ({auth: {token: openAIToken}});
final pinecone:Client pineconeClient = check new ({apiKey: pineconeKey}, serviceUrl = pineconeServiceUrl);

const MAXIMUM_NO_OF_DOCS = 5;
const MAXIMUM_NO_OF_WORDS = 1000;
const NAMESPACE = "SampleData";
const EMBEDDING_MODEL = "text-embedding-ada-002";
const COMPLETION_MODEL = "text-davinci-003";

function getEmbedding(string text) returns float[]|error {
    embeddings:CreateEmbeddingResponse embeddingRes = check openaiEmbeddings->/embeddings.post({
        input: text,
        model: EMBEDDING_MODEL
    });
    return embeddingRes.data[0].embedding;
}

function countWords(string text) returns int => regex:split(text, " ").length();

function constructPrompt(string question) returns string|error {
    string context = "";
    int contextLen = 0;

    // implement the logic to construct the context
    float[] questionEmbedding = check getEmbedding(question);

    pinecone:QueryResponse queryRes = check pineconeClient->/query.post({
        namespace: NAMESPACE,
        vector: questionEmbedding,
        topK: MAXIMUM_NO_OF_DOCS,
        includeMetadata: true
    });
    pinecone:QueryMatch[]? matches = queryRes.matches;

    if matches is () {
        return error("No matches found");
    }

    foreach pinecone:QueryMatch doc in matches {
        string content = doc.metadata["content"].toString();
        contextLen += countWords(content);
        if (contextLen > MAXIMUM_NO_OF_WORDS) {
            break;
        }
        context += content + "\n";
    }
    
    string instruction = "Answer the question as truthfully as possible using the provided context," +
    " and if the answer is not contained within the text below, say \"I don't know.\"\n\n";

    return string `${instruction}Context:${"\n"} ${context} ${"\n\n"} Q: ${question} ${"\n"} A:`;
}

service / on new http:Listener(8080) {

    resource function get answer(string question) returns string?|error {
        string prompt = check constructPrompt(question);
        text:CreateCompletionResponse completionRes = check openAIText->/completions.post({
            prompt,
            model: COMPLETION_MODEL,
            max_tokens: 200,
            temperature: 0.3
        });
        return completionRes.choices[0].text;
    }
}
