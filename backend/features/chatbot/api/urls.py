from django.urls import path

from features.chatbot.api.views import chat_endpoint

urlpatterns = [
    path('api/chat/', chat_endpoint, name='chat-endpoint'),
]
