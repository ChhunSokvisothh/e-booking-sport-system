from django.urls import path

from features.chatbot.api.views import (
    chat_endpoint,
    chat_session_messages_endpoint,
    chat_sessions_endpoint,
)

urlpatterns = [
    path('api/chat/', chat_endpoint, name='chat-endpoint'),
    path('api/chat/sessions/', chat_sessions_endpoint, name='chat-sessions'),
    path('api/chat/sessions/<str:session_id>/', chat_session_messages_endpoint, name='chat-session-messages'),
]
